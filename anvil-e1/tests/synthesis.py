"""Real Yosys synthesis and structural assertions for both admitted geometries."""
import json
from pathlib import Path

from model import CONFIGS


def verify_synthesis(execution, configs, probe=False):
    if configs != ["A","B"] and not (probe and configs == ["A"]):
        raise ValueError("synthesis requires configurations A and B")
    ledger = []
    for config in configs:
        execution.remaining()
        output = execution.output
        netlist = output/f"{config}-netlist.json"
        script = output/f"{config}.ys"
        parameters = " ".join(f"-set {n} {v}"
                              for n,v in CONFIGS[config].parameters().items())
        script.write_text("read_verilog -sv -defer "+
            " ".join(str(p) for p in sorted(Path("rtl").glob("*.sv")))+"\n"+
            "hierarchy -check -top anvil_e1_top "+
            parameters.replace("-set ", "-chparam ")+"\nproc\nopt\nmemory\nopt\n"+
            "check -assert\nstat\n"+f"write_json {netlist}\n")
        log = execution.run("yosys-"+config,["yosys","-s",str(script)])
        modules = json.loads(netlist.read_text())["modules"]
        assert "anvil_e1_top" in modules
        visited = set()
        names = set()
        sequential = arithmetic = 0
        def visit(name):
            nonlocal sequential,arithmetic
            if name in visited: return
            visited.add(name)
            module = modules[name]
            assert not int(module.get("attributes",{}).get("blackbox","0"),2)
            hdlname = module.get("attributes",{}).get("hdlname",name).split()[0].lstrip("\\")
            names.add(hdlname)
            for cell in module["cells"].values():
                kind = cell["type"]
                assert "latch" not in kind.lower(), kind
                assert cell.get("connections"), (name,kind,"disconnected")
                if kind in modules:
                    visit(kind)
                elif kind.startswith("$"):
                    assert not kind.startswith("$tribuf")
                    sequential += "dff" in kind.lower()
                    arithmetic += kind in ("$mul","$div","$mod","$add","$sub","$shift","$sshr")
                else:
                    raise AssertionError(f"unresolved/blackbox DUT cell {kind}")
        visit("anvil_e1_top")
        required = {"anvil_e1_"+n for n in (
            "top","controller","memory","mac","nonlinear","norm","attention",
            "pool","sequencer","matvec","rope")}
        assert required <= names, required-names
        assert sequential >= 20 and arithmetic >= 20, (sequential,arithmetic)
        ledger.append({"config":config,"status":"passed","modules":sorted(names),
            "sequential_cells":sequential,"arithmetic_cells":arithmetic,
            "netlist":str(netlist),"statistics_log":str(log)})
        (output/"synthesis-summary.json").write_text(json.dumps(ledger,indent=2)+"\n")
