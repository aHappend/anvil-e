"""Independent packed tensor and scratch address boundaries, including overflow."""
import json
import re
from pathlib import Path

from model import CONFIGS, inventory


def verify_addresses(execution):
    from architecture import DEFAULT
    ledger = []
    for config,g in {"default":DEFAULT,**CONFIGS}.items():
        execution.remaining()
        entries = inventory(g)
        total = sum(e["size_bytes"] for e in entries)
        counts = [g.S*g.H,g.S*g.L*g.P,g.S*g.QH*max(g.LD,g.FD),
                  g.S*max(g.LK,g.FK)*max(g.LD,g.FD)]
        counts += [counts[3],counts[0]]
        scratch = sum(counts)*4
        cases, expected = [], []
        def add(tid,layer,element,region=0,word=0,wb=4096,sb=524288):
            tag=len(cases)
            cases.append(f"{tag} {wb:x} {sb:x} {g.S} {tid} {layer} "
                         f"{element:x} {region} {word:x}\n")
            entry = (entries[tid] if tid<5 else
                     entries[5+layer*17+tid-5] if tid<22 and layer<g.L else None)
            if entry is None:
                # Invalid selections still expose shape/address; only rejection is contracted.
                tensor = None
            else:
                shape=entry["shape"]
                rows,cols=shape[0],shape[1] if len(shape)>1 else 1
                address=wb+entry["offset_bytes"]+element*4
                tensor=[address & ((1<<64)-1),rows,cols,
                        int(element>=rows*cols or address>=1<<64)]
            address=sb+(sum(counts[:region])+word)*4 if region<6 else sb+word*4
            serr=int(region>=6 or word>=(counts[region] if region<6 else 0)
                     or address>=1<<64)
            expected.append((tensor,[address & ((1<<64)-1),serr,total,scratch,tag]))
        for i,e in enumerate(entries):
            tid=i if i<5 else 5+(i-5)%17
            layer=0 if i<5 else (i-5)//17
            for index in (0,e["size_bytes"]//4-1,e["size_bytes"]//4):
                add(tid,layer,index)
            add(tid,layer,0,wb=(1<<64)-4)
        for region,count in enumerate(counts):
            for word in (0,count-1,count):
                add(0,0,0,region,word)
            add(0,0,0,region,count-1,sb=(1<<64)-4)
        add(22,0,0)
        add(5,g.L,0)
        add(0,0,0,6)
        inputs=execution.output/f"addresses-{config}.txt"
        inputs.write_text("".join(cases))
        binary=execution.output/f"addresses-{config}.vvp"
        overrides={n:v for n,v in g.parameters().items()
                   if n not in ("SLIDING_WINDOW","MAX_SEQ_LEN")}
        execution.run("address-compile-"+config,["iverilog","-g2012","-s","addresses",
            "-o",str(binary)]+[f"-Paddresses.{n}={v}" for n,v in overrides.items()]+
            ["tests/addresses.sv","rtl/anvil_e1_address.sv"])
        trace=execution.run("address-run-"+config,["vvp",str(binary),f"+input={inputs}"])
        seen=set()
        complete=None
        for line in trace.read_text().splitlines():
            fields=line.split()
            if fields and fields[0]=="ADDRESS":
                values=list(map(int,fields[1:]))
                assert len(values)==10
                tag=values[0]
                assert tag not in seen and 0<=tag<len(expected)
                seen.add(tag)
                tensor,tail=expected[tag]
                if tensor is None:
                    assert values[4]==1, (config,tag,"invalid index accepted")
                else:
                    assert values[1:5]==tensor, (config,tag,values,tensor)
                assert values[5:]==tail, (config,tag,values,tail)
            elif fields and fields[0]=="COMPLETE":
                assert complete is None
                complete=int(fields[1])
            elif not re.fullmatch(r"tests/addresses\.sv:\d+: \$finish called at \d+ \([^)]+\)",line):
                raise AssertionError("unexpected address diagnostic: "+line)
        assert complete==len(cases) and len(seen)==len(cases)
        ledger.append({"config":config,"tensors":len(entries),"compared":len(cases),
                       "weights_bytes":total,"scratch_bytes":scratch})
    (execution.output/"address-summary.json").write_text(json.dumps(ledger,indent=2)+"\n")
