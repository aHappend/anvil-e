"""Bounded, explicitly incomplete public-pin execution-cost probe."""
import argparse
import dataclasses
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Fixture, Integer, SCRATCH
from verify import ROOT, Run, bench, rtl_files


def replay_host(run, fixture, memory, transcript):
    """Measure only the real responder's recorded lookups, not inference."""
    requests = [line.split()[1:] for line in transcript.splitlines()
                if line.startswith("T ")]
    assert requests
    trace = run.directory/"requests.trace"
    trace.write_text("".join(" ".join(row)+"\n" for row in requests))
    words = (fixture.layout["end"]-SCRATCH)//4
    text = f"""
module host_replay;
reg clk=0;
always #5 clk=~clk;
reg [63:0] addresses[0:{len(fixture.mem)-1}];
reg [31:0] values[0:{len(fixture.mem)-1}];
reg [31:0] scratch[0:{words-1}];
reg initialized[0:{words-1}];
integer fd,tf,rc,count=0,cycles=0,target,write_flag,entry,lo,hi,mid,i,requests=0;
reg [63:0] address;
reg [31:0] data,expected,actual;
initial begin
 for(i=0;i<{words};i=i+1) initialized[i]=0;
 fd=$fopen("{memory}","r");
 if(!fd) $fatal(1,"REPLAY_MEMORY");
 while(!$feof(fd)) begin
  rc=$fscanf(fd,"%h %h\\n",addresses[count],values[count]);
  if(rc==2) count=count+1;
 end
 $fclose(fd);
 tf=$fopen("{trace}","r"); if(!tf) $fatal(1,"REPLAY_TRACE");
 for(i=0;i<{len(requests)};i=i+1) begin
  rc=$fscanf(tf,"%d %h %d %h %h\\n",target,address,write_flag,data,expected);
  if(rc!=5) $fatal(1,"REPLAY_FORMAT");
  while(cycles<target) begin @(posedge clk); cycles=cycles+1; end
  actual=0;
  if(write_flag) begin
   entry=(address-64'h{SCRATCH:x})/4;
   if(entry<0 || entry>={words}) $fatal(1,"REPLAY_WRITE_ADDRESS");
   scratch[entry]=data; initialized[entry]=1;
   $display("W %h %h",address,data);
  end else if(address>=64'h{SCRATCH:x} && address<64'h{fixture.layout["end"]:x}) begin
   entry=(address-64'h{SCRATCH:x})/4;
   if(!initialized[entry]) $fatal(1,"REPLAY_UNINITIALIZED");
   actual=scratch[entry];
  end else begin
   lo=0; hi=count-1; entry=-1;
   while(lo<=hi) begin
    mid=(lo+hi)/2;
    if(addresses[mid]==address) begin entry=mid; lo=hi+1; end
    else if(addresses[mid]<address) lo=mid+1;
    else hi=mid-1;
   end
   if(entry<0) $fatal(1,"REPLAY_READ_ADDRESS");
   actual=values[entry];
  end
  if(actual!==expected) $fatal(1,"REPLAY_READ_VALUE");
  requests=requests+1;
 end
 $fclose(tf);
 $display("HOST_REPLAY_COMPLETE cycles=%0d requests=%0d",cycles,requests);
 $finish;
end
endmodule
"""
    tb, exe = run.directory/"host.sv", run.directory/"host.vvp"
    tb.write_text(text)
    run.command(["iverilog", "-g2012", "-Wall", "-s", "host_replay",
                 "-o", exe, tb], "host-compile", timeout=10)
    out, _, _ = run.command(["vvp", "-v", exe], "host-simulate", timeout=10)
    assert f"requests={len(requests)}" in out and "HOST_REPLAY_COMPLETE" in out
    run.receipt["assertions"].append({
        "host_replay_only": True, "compared_requests": len(requests),
        "compared_read_responses": sum(row[2] == "0" for row in requests),
        "limitation": "Measures recorded responder lookups, scratch and clock events; "
                      "excludes DUT and public protocol monitors; not hardware acceptance.",
    })
    run.save()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--cycles", type=int, default=300000)
    parser.add_argument("--host-replay", action="store_true")
    parser.add_argument("--configuration", choices=("B", "C"), default="B")
    parser.add_argument("--repair-of",
                        default="evidence/preparation/q40-divider-b-joint-002/receipt.json")
    args = parser.parse_args()
    directory = (ROOT / args.output).resolve()
    assert directory.is_relative_to(ROOT / "evidence/preparation")
    assert 0 < args.cycles <= 300000
    assert not args.host_replay or args.cycles <= 100000
    run = Run(directory, budget=60, repair_of=args.repair_of)
    try:
        run.tools(("python3", "iverilog", "vvp"))
        fixture = Fixture(CONFIGS[args.configuration], 17, 2)
        _, expected = fixture.run(Integer())
        run.receipt["fixture"] = {
            "configuration": dataclasses.asdict(fixture.c), "seed": 17,
            "mode": 2, "diagnostic_only": True,
            "expected_write_count": sum(map(len, expected.values())),
        }
        memory = directory / "input.mem"
        memory.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                                 for a, v in sorted(fixture.mem.items())))
        text = bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4)
        text = text.replace("integer fd,rc", "integer write_count=0;\n"
                            "reg [63:0] latest_address=0;\ninteger fd,rc")
        text = text.replace("pending=1; response_at=", "latest_address=mem_req_addr;\n"
                            "   pending=1; response_at=")
        text = text.replace('$display("W %h %h",mem_req_addr,mem_req_wdata);',
                            'write_count=write_count+1;\n'
                            '     $display("W %h %h",mem_req_addr,mem_req_wdata);')
        if args.host_replay:
            text = text.replace("mem_rsp_rdata=read_value;", """
   mem_rsp_rdata=read_value;
   $display("T %0d %h %0d %h %h",cycles,mem_req_addr,mem_req_write,mem_req_wdata,read_value);
""")
        text = text.replace("endmodule", f"""
always @(negedge clk) if(rst_n && cycles%10000==0) begin
 $display("PROGRESS time=%0t cycles=%0d requests=%0d responses=%0d writes=%0d latest=%h",
          $time,cycles,requests,responses,write_count,latest_address);
 $fflush();
 if(cycles>={args.cycles}) begin
  $display("DIAGNOSTIC_STOP_INCOMPLETE"); $fflush(); $finish;
 end
end
endmodule
""")
        tb, executable = directory/"progress.sv", directory/"progress.vvp"
        tb.write_text(text)
        run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o",
                     executable, *rtl_files(), tb], "compile", timeout=20)
        try:
            run.command(["vvp", "-v", executable], "simulate", timeout=45)
        finally:
            stdout = (directory/"simulate.stdout").read_text()
            observed = {}
            for line in stdout.splitlines():
                fields = line.split()
                if fields and fields[0] == "W":
                    observed.setdefault(int(fields[1], 16), []).append(int(fields[2], 16))
            mismatches = [hex(a) for a, values in observed.items()
                          if a not in expected or values != expected[a][:len(values)]]
            run.receipt["assertions"].append({
                "compared_prefix_writes": sum(map(len, observed.values())),
                "compared_addresses": len(observed), "mismatches": mismatches,
                "public_progress": [line for line in stdout.splitlines()
                                    if line.startswith("PROGRESS ")],
                "full_fixture_complete": "TRANSCRIPT_COMPLETE" in stdout,
                "diagnostic_stop": "DIAGNOSTIC_STOP_INCOMPLETE" in stdout,
            })
            run.save()
            assert not mismatches, f"integer write-prefix mismatch: {mismatches}"
        if args.host_replay:
            replay_host(run, fixture, memory, stdout)
        run.finish("diagnostic-incomplete")
    except Exception as error:
        timed_out = any(record.get("timed_out") for record in run.receipt["executions"])
        run.finish("diagnostic-incomplete" if timed_out else "failed", str(error))
    print(json.dumps({"status": run.receipt["status"],
                      "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
    return int(run.receipt["status"] == "failed")


if __name__ == "__main__":
    sys.exit(main())
