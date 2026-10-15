"""Public matvec/MAC boundary checks; expectations are dense tensor equations."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import Integer, ONE, Q
from verify import ROOT, Run, rtl_files


def boundaries(run, directory=None, prefix="cursor"):
    cases = [
        ("singleton", 1, 1, 0x12340, -1, ""),
        ("final-row-single-column", 3, 1, 0xfffffff8, -1, ""),
        ("single-row", 1, 3, 0x12340, -1, ""),
        ("nonpower-final-row", 3, 3, 0xfffffff8, -1, ""),
        ("near-last-address", 1, 1, 0xfffffffffffffff8, -1, ""),
        ("first-weight-error", 3, 3, 0x12340, 0, ""),
        ("row-final-error", 3, 3, 0x12340, 2, ""),
        ("last-weight-error", 3, 3, 0x12340, 8, ""),
        ("reset-request", 3, 3, 0x12340, -1, "request"),
        ("reset-response", 3, 3, 0x12340, -1, "response"),
        ("reset-output", 3, 3, 0x12340, -1, "output"),
    ]
    summaries = []
    for case, rows, cols, base, error_at, reset in cases:
        name = f"{prefix}-{case}"
        inputs = [(-1 if j % 2 else 1)*(ONE//(j+2)+12345) for j in range(cols)]
        weights = [(-1 if i % 3 else 1)*(Q//(i+3)+71) for i in range(rows*cols)]
        expected = Integer().mat(
            [[v << 16 for v in weights[i*cols:(i+1)*cols]] for i in range(rows)],
            inputs)
        assignments = "\n".join(
            [f"x[{i}]=48'h{v & ((1 << 48)-1):012x};" for i, v in enumerate(inputs)] +
            [f"w[{i}]=32'h{v & 0xffffffff:08x};" for i, v in enumerate(weights)] +
            [f"y[{i}]=48'h{v & ((1 << 48)-1):012x};" for i, v in enumerate(expected)])
        reset_condition = {
            "": "0", "request": "cmd_valid && !cmd_ready",
            "response": "pending && !result_valid",
            "output": "out_valid && !out_ready",
        }[reset]
        text = f"""
module tb;
reg clk=0,rst_n=0,start_valid=0,in_valid=0,cmd_ready=0,result_valid=0;
reg result_error=0,out_ready=0,done_ready=0;
reg [31:0] start_rows={rows},start_cols={cols},result_data=0;
reg [63:0] start_weights=64'h{base:x};
reg signed [47:0] in_data=0;
wire start_ready,in_ready,cmd_valid,result_ready,mac_clear,mac_accumulate;
wire out_valid,out_last,done_valid;
wire [63:0] cmd_addr;
wire signed [47:0] mac_a,mac_b,mac_rounded,out_data;
wire [31:0] out_index;
wire [3:0] done_error;
wire signed [127:0] sum;
wire signed [95:0] product;
anvil_e2_matvec #(.MAX_INPUT(3)) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_rows(start_rows),.start_cols(start_cols),.start_weights(start_weights),
 .in_valid(in_valid),.in_ready(in_ready),.in_data(in_data),
 .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
 .result_valid(result_valid),.result_ready(result_ready),.result_data(result_data),
 .result_error(result_error),.mac_clear(mac_clear),.mac_accumulate(mac_accumulate),
 .mac_a(mac_a),.mac_b(mac_b),.mac_rounded(mac_rounded),
 .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),
 .out_index(out_index),.out_last(out_last),.done_valid(done_valid),
 .done_ready(done_ready),.done_error(done_error));
anvil_e2_mac mac(.clk(clk),.rst_n(rst_n),.clear(mac_clear),
 .accumulate(mac_accumulate),.a(mac_a),.b(mac_b),.sum(sum),
 .rounded(mac_rounded),.product(product));
always #5 clk=~clk;
reg signed [47:0] x[0:{cols-1}],y[0:{rows-1}];
reg signed [31:0] w[0:{rows*cols-1}];
integer cycles=0,loaded=0,requests=0,responses=0,outputs=0,accumulations=0;
integer response_cycle=-1,request_cycle=-1,first_cmd=-1,first_out=-1,first_done=-1;
integer reqstalls=0,rspwait=0,outstalls=0,donestalls=0;
reg active=0,pending=0,retired_error=0,held_cmd=0,held_out=0,held_done=0;
reg [63:0] held_addr;
reg [80:0] held_output;
task automatic known;
begin
 if((^{{start_ready,in_ready,cmd_valid,cmd_addr,result_ready,
   mac_clear,mac_accumulate,mac_a,mac_b,out_valid,out_data,out_index,out_last,
   done_valid,done_error}})===1'bx) $fatal(1,"CURSOR_XZ");
 if(!rst_n && {{start_ready,in_ready,cmd_valid,cmd_addr,result_ready,
   mac_clear,mac_accumulate,mac_a,mac_b,out_valid,out_data,out_index,out_last,
   done_valid,done_error}}!=='0) $fatal(1,"CURSOR_RESET");
end
endtask
initial begin {assignments}
 #1; known(); #11; rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1; if(cycles>1000) $fatal(1,"CURSOR_TIMEOUT");
  start_valid=!active && cycles>2;
  in_valid=active && loaded<{cols} && cycles%3!=0;
  in_data=loaded<{cols} ? x[loaded]:48'sd0;
  if(cmd_valid && first_cmd<0) first_cmd=cycles;
  cmd_ready=first_cmd>=0 && cycles>first_cmd+4 && cycles%7>=3;
  result_valid=pending && cycles>=response_cycle;
  if(out_valid && first_out<0) first_out=cycles;
  out_ready=first_out>=0 && cycles>first_out+7 && cycles%3==0;
  if(done_valid && first_done<0) first_done=cycles;
  done_ready=first_done>=0 && cycles>first_done+8;
  if({reset_condition}) begin
   rst_n=0; start_valid=0; in_valid=0; result_valid=0; pending=0;
   #1; known(); #11; rst_n=1;
   #10; if(start_ready!==1 || cmd_valid!==0 || out_valid!==0 || done_valid!==0)
     $fatal(1,"CURSOR_RESET_RESUMED");
   $display("CURSOR_RESET_COMPLETE {reset}"); $finish;
  end
 end
end
always @(posedge clk) begin
 known();
 $display("P %0d %h",cycles,{{start_ready,in_ready,cmd_valid,cmd_addr,result_ready,
   mac_clear,mac_accumulate,mac_a,mac_b,out_valid,out_data,out_index,out_last,
   done_valid,done_error}});
 if(rst_n) begin
  if(held_cmd && (!cmd_valid || cmd_addr!==held_addr)) $fatal(1,"CURSOR_REQUEST_STALL");
  if(held_out && (!out_valid || {{out_data,out_index,out_last}}!==held_output))
   $fatal(1,"CURSOR_OUTPUT_STALL");
  if(held_done && (!done_valid || done_error!==4'd{3 if error_at >= 0 else 0}))
   $fatal(1,"CURSOR_DONE_STALL");
  held_cmd=cmd_valid && !cmd_ready; held_addr=cmd_addr;
  held_out=out_valid && !out_ready; held_output={{out_data,out_index,out_last}};
  held_done=done_valid && !done_ready;
  if(held_cmd) reqstalls=reqstalls+1;
  if(pending && !result_valid) rspwait=rspwait+1;
  if(held_out) outstalls=outstalls+1;
  if(held_done) donestalls=donestalls+1;
  if(start_valid && start_ready) begin
   if(active) $fatal(1,"CURSOR_DUPLICATE"); active=1;
  end
  if(in_valid && in_ready) loaded=loaded+1;
  if(mac_accumulate) begin
   if(!(result_valid && result_ready) || result_error ||
      mac_a!==x[responses%{cols}] || mac_b!=={{w[responses],16'd0}} ||
      mac_clear!==(responses%{cols}==0)) $fatal(1,"CURSOR_MAC");
   accumulations=accumulations+1;
  end
  if(result_valid && result_ready) begin
   if(!pending || cycles<=request_cycle) $fatal(1,"CURSOR_RESPONSE");
   pending=0; responses=responses+1;
   if(result_error) retired_error=1;
  end
  if(retired_error && cmd_valid) $fatal(1,"CURSOR_REQUEST_AFTER_ERROR");
  if(cmd_valid && cmd_ready) begin
   if(!active || pending || requests>={rows*cols} ||
      cmd_addr!==64'h{base:x}+64'd4*requests) $fatal(1,"CURSOR_ORDER");
   pending=1; request_cycle=cycles; response_cycle=cycles+4+requests%3;
   result_data=w[requests]; result_error=(requests=={error_at});
   requests=requests+1;
  end
  if(out_valid && out_ready) begin
   if(outputs>={rows} || out_index!==outputs ||
      out_last!==(outputs=={rows-1}) || out_data!==y[outputs])
     $fatal(1,"CURSOR_DENSE_RESULT");
   outputs=outputs+1;
  end
  if(done_valid && done_ready) begin
   if(pending || requests!=responses || requests!={error_at+1 if error_at>=0 else rows*cols} ||
      outputs!={error_at//cols if error_at>=0 else rows} ||
      accumulations!={error_at if error_at>=0 else rows*cols} ||
      done_error!==4'd{3 if error_at>=0 else 0} || reqstalls==0 || rspwait==0 ||
      donestalls<8 || ({int(error_at<0)} && outstalls<7))
     $fatal(1,"CURSOR_COMPLETION");
   $display("CURSOR_COMPLETE %0d %0d %0d %0d",requests,responses,outputs,accumulations);
   $finish;
  end
  #1; if(active) begin start_rows=99; start_cols=99; start_weights=64'hbad; end
 end
end
endmodule
"""
        tb = run.directory / (name + ".sv")
        tb.write_text(text)
        executable = run.directory / (name + ".vvp")
        run.receipt.setdefault("generated_source_sha256", {})[
            str(tb.relative_to(ROOT))] = hashlib.sha256(tb.read_bytes()).hexdigest()
        run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable,
                     *rtl_files(directory), tb], name+"-compile", timeout=5)
        out, _, _ = run.command(["vvp", executable], name+"-simulate", timeout=5)
        assert out.count("CURSOR_RESET_COMPLETE " if reset else "CURSOR_COMPLETE ") == 1
        record = {
            "case": name, "rows": rows, "cols": cols, "base": base,
            "error_weight_index": error_at, "reset_phase": reset or None,
            "expected_q40": expected,
            "public_samples_sha256": hashlib.sha256("\n".join(
                line for line in out.splitlines() if line.startswith("P ")).encode()).hexdigest(),
            "transcript": str((run.directory / (name+"-simulate.stdout")).relative_to(ROOT)),
        }
        summaries.append(record)
        run.receipt["coverage"].append(record)
        run.save()
    return summaries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--before-directory")
    args = parser.parse_args()
    directory = (ROOT / args.output).resolve()
    assert directory.is_relative_to(ROOT / "evidence/preparation")
    run = Run(directory, budget=60)
    try:
        run.tools(("python3", "iverilog", "vvp"))
        current = boundaries(run)
        if args.before_directory:
            before = (ROOT / args.before_directory).resolve()
            assert before.is_relative_to(ROOT / "evidence/preparation")
            run.receipt["baseline_source_sha256"] = {
                str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in rtl_files(before)}
            original = boundaries(run, before, "before")
            assert [c["public_samples_sha256"] for c in current] == [
                c["public_samples_sha256"] for c in original], "public cycle behavior changed"
            run.receipt["assertions"].append(
                "All sampled public helper pins, including inactive addresses, match before/after.")
    except Exception as error:
        (directory / "diagnostic.stderr").write_text(traceback.format_exc())
        run.finish("failed", str(error))
        traceback.print_exc()
        return 1
    run.finish("passed")
    print(json.dumps({"cases": len(run.receipt["coverage"]), "status": "passed"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
