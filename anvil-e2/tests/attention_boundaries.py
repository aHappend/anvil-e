"""Public attention traversal tests from padded tensor addresses and softmax."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import Integer, ONE, Q, clamp40, rnd
from verify import ROOT, Run, rtl_files


def scenario(vision, full, head, kind):
    n = 1 if kind == "singleton" else 5
    dim = 6 if full else 2
    query = n-1
    positions = [7, 10, 8, 11, 9][:n]
    masks = [1, 0, 1, 1, 1][:n]
    if kind == "empty":
        masks = [0]*n
    if kind == "final-skipped":
        masks[-1] = 0
    base = 0xffffffe0 if kind == "carry" else 0x123400
    qb, kb, vb, pb, mb = [base+i*0x10000 for i in range(5)]
    kh = head // (4 // (1 if full else 2))
    q = [(j+1)*Q//3 for j in range(dim)]
    ks = [[(-1 if (i+j)%2 else 1)*(i+j+1)*Q//5
           for j in range(dim)] for i in range(n)]
    if kind == "tail":
        ks[0] = [-40*Q]*dim
    vs = [[(-1 if (i+j)%3 else 1)*(2*i+j+1)*Q//7
           for j in range(dim)] for i in range(n)]
    eligible = [i for i in range(n) if vision or (
        masks[i] and (full or abs(positions[i]-positions[query]) < 2))]
    scores = {i: clamp40(rnd(sum(a*b for a, b in zip(q, ks[i])) << 32,
                            math.isqrt(dim << 80))) for i in eligible}
    maximum = max(scores.values(), default=0)
    weighted_keys = [i for i in eligible if scores[i]-maximum >= -16*ONE]
    if kind == "tail":
        assert eligible and len(weighted_keys) < len(eligible)
    requests = [(qb+4*(query*4*6+head*dim+j), q[j], "Q") for j in range(dim)]
    if not vision:
        requests.append((pb+4*query, positions[query], "query-position"))
    # Architectural traversal: maximum reduction, then weighted reduction.
    for pass_index in range(2 if eligible else 1):
        for i in range(n):
            if not vision:
                requests.append((mb+4*i, masks[i], f"mask{pass_index}"))
                if not masks[i]:
                    continue
                if not full:
                    requests.append((pb+4*i, positions[i], f"position{pass_index}"))
            if i not in eligible:
                continue
            requests.extend((kb+4*(i*2*6+kh*dim+j), ks[i][j], f"K{pass_index}")
                            for j in range(dim))
            if pass_index and i in weighted_keys:
                requests.extend((vb+4*(i*2*6+kh*dim+j), vs[i][j], "V")
                                for j in range(dim))
    expected = Integer().attention([a << 16 for a in q],
                                  [[a << 16 for a in ks[i]] for i in eligible],
                                  [[a << 16 for a in vs[i]] for i in eligible])
    return n, dim, query, (qb, kb, vb, pb, mb), requests, expected, eligible, weighted_keys


def boundaries(run, directory=None, prefix="attention"):
    cases = [(v, f, h, "mixed", "", None) for v in (0, 1)
             for f in (0, 1) for h in range(4)]
    cases += [(0, 0, 3, k, "", None)
              for k in ("singleton", "empty", "final-skipped", "carry")]
    cases += [(1, 1, 3, "tail", "", None), (1, 0, 3, "singleton", "", None)]
    cases += [(0, 0, 3, "mixed", phase, None)
              for phase in ("idle", "request", "response", "output")]
    cases += [(0, 0, 3, "mixed", "", tag)
              for tag in ("Q:first", "Q:last", "query-position:first",
                          "mask0:first", "position0:first", "K0:first", "K0:last",
                          "mask1:last", "position1:last", "K1:last",
                          "V:first", "V:last")]
    summaries = []
    for index, (vision, full, head, kind, reset, fault) in enumerate(cases):
        name = f"{prefix}-{index:02d}"
        n, dim, query, bases, requests, expected, eligible, weighted_keys = scenario(
            vision, full, head, kind)
        error_at = -1
        if fault:
            tag, end = fault.split(":")
            indices = [i for i, r in enumerate(requests) if r[2] == tag]
            assert indices, fault
            error_at = indices[0 if end == "first" else -1]
        count = error_at+1 if fault else len(requests)
        assignments = "\n".join(
            [f"addresses[{i}]=64'h{a:x}; words[{i}]=32'h{b & 0xffffffff:08x};"
             for i, (a, b, _) in enumerate(requests)] +
            [f"expected[{i}]=48'h{v & ((1 << 48)-1):012x};"
             for i, v in enumerate(expected)])
        reset_condition = {
            "": "0", "idle": "cycles==2",
            "request": "cmd_valid && !cmd_ready",
            "response": "pending && !result_valid",
            "output": "out_valid && !out_ready",
        }[reset]
        text = f"""
module tb;
reg clk=0,rst_n=0,start_valid=0,cmd_ready=0,result_valid=0,result_error=0;
reg out_ready=0,done_ready=0;
reg [31:0] start_tokens={n},start_query={query},start_head={head},result_data=0;
reg start_full={full};
reg [63:0] qb=64'h{bases[0]:x},kb=64'h{bases[1]:x},vb=64'h{bases[2]:x};
reg [63:0] pb=64'h{bases[3]:x},mb=64'h{bases[4]:x};
wire start_ready,cmd_valid,result_ready,mac_clear,mac_accumulate;
wire [63:0] cmd_addr;
wire signed [47:0] mac_a,mac_b,mac_rounded,out_data;
wire signed [127:0] mac_sum;
wire signed [95:0] mac_product;
wire nonlinear_valid,nonlinear_ready,nonlinear_out_valid,nonlinear_out_ready,nonlinear_out_error;
wire [2:0] nonlinear_op;
wire signed [47:0] nonlinear_data,nonlinear_out_data;
wire out_valid,out_last,done_valid;
wire [31:0] out_index;
wire [3:0] done_error;
anvil_e2_attention #(.NUM_Q_HEADS(4),.LOCAL_KV_HEADS(2),.FULL_KV_HEADS(1),
 .LOCAL_HEAD_DIM(2),.FULL_HEAD_DIM(6),.SLIDING_WINDOW(2),.VISION({vision})) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_tokens(start_tokens),.start_query(start_query),.start_head(start_head),
 .start_full(start_full),.start_q_base(qb),.start_k_base(kb),.start_v_base(vb),
 .start_positions_base(pb),.start_mask_base(mb),
 .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
 .result_valid(result_valid),.result_ready(result_ready),.result_data(result_data),
 .result_error(result_error),.mac_clear(mac_clear),.mac_accumulate(mac_accumulate),
 .mac_a(mac_a),.mac_b(mac_b),.mac_sum(mac_sum),.mac_product(mac_product),
 .nonlinear_valid(nonlinear_valid),.nonlinear_ready(nonlinear_ready),
 .nonlinear_op(nonlinear_op),.nonlinear_data(nonlinear_data),
 .nonlinear_out_valid(nonlinear_out_valid),.nonlinear_out_ready(nonlinear_out_ready),
 .nonlinear_out_data(nonlinear_out_data),.nonlinear_out_error(nonlinear_out_error),
 .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),
 .out_index(out_index),.out_last(out_last),.done_valid(done_valid),
 .done_ready(done_ready),.done_error(done_error));
anvil_e2_mac mac(.clk(clk),.rst_n(rst_n),.clear(mac_clear),.accumulate(mac_accumulate),
 .a(mac_a),.b(mac_b),.sum(mac_sum),.rounded(mac_rounded),.product(mac_product));
anvil_e2_nonlinear nonlinear(.clk(clk),.rst_n(rst_n),
 .in_valid(nonlinear_valid),.in_ready(nonlinear_ready),.in_op(nonlinear_op),
 .in_data(nonlinear_data),.out_valid(nonlinear_out_valid),
 .out_ready(nonlinear_out_ready),.out_data(nonlinear_out_data),.out_error(nonlinear_out_error));
always #5 clk=~clk;
reg [63:0] addresses[0:{len(requests)-1}];
reg [31:0] words[0:{len(requests)-1}];
reg signed [47:0] expected[0:{dim-1}];
integer cycles=0,requests=0,responses=0,outputs=0,request_cycle=-1,response_cycle=-1;
integer first_out=-1,first_done=-1,reqstalls=0,rspwait=0,outstalls=0,donestalls=0;
integer first_cmd=-1;
reg active=0,pending=0,retired_error=0,held_cmd=0,held_out=0,held_done=0;
reg [63:0] held_addr;
reg [80:0] held_output;
task automatic sample;
begin
 if((^{{start_ready,cmd_valid,cmd_addr,result_ready,mac_clear,mac_accumulate,mac_a,mac_b,
 nonlinear_valid,nonlinear_op,nonlinear_data,nonlinear_out_ready,
 out_valid,out_data,out_index,out_last,done_valid,done_error}})===1'bx)
  $fatal(1,"ATTENTION_XZ");
 if(!rst_n && {{start_ready,cmd_valid,cmd_addr,result_ready,mac_clear,mac_accumulate,
 mac_a,mac_b,nonlinear_valid,nonlinear_op,nonlinear_data,nonlinear_out_ready,
 out_valid,out_data,out_index,out_last,done_valid,done_error}}!=='0)
  $fatal(1,"ATTENTION_RESET");
 if(!cmd_valid && cmd_addr!==0) $fatal(1,"ATTENTION_INACTIVE_ADDRESS");
 $display("P %0t %h",$time,{{start_ready,cmd_valid,cmd_addr,result_ready,
 mac_clear,mac_accumulate,mac_a,mac_b,nonlinear_valid,nonlinear_op,nonlinear_data,
 nonlinear_out_ready,out_valid,out_data,out_index,out_last,done_valid,done_error}});
end
endtask
initial begin {assignments}
 #1; sample(); #11; rst_n=1;
end
always @(negedge clk) begin
 sample();
 if(rst_n) begin
  cycles=cycles+1; if(cycles>20000) $fatal(1,"ATTENTION_TIMEOUT");
  start_valid=!active && cycles>2;
  if(cmd_valid && first_cmd<0) first_cmd=cycles;
  cmd_ready=first_cmd>=0 && cycles>first_cmd+4 && cycles%9>=4;
  result_valid=pending && cycles>=response_cycle;
  if(out_valid && first_out<0) first_out=cycles;
  out_ready=first_out>=0 && cycles>first_out+8 && cycles%3==0;
  if(done_valid && first_done<0) first_done=cycles;
  done_ready=first_done>=0 && cycles>first_done+9;
  if(active) begin
   start_tokens=0; start_query=99; start_head=99; start_full=!{full};
   qb=64'hbad; kb=64'hbad; vb=64'hbad; pb=64'hbad; mb=64'hbad;
  end
  if({reset_condition}) begin
   rst_n=0; start_valid=0; result_valid=0; pending=0;
   #1; sample(); #11; rst_n=1;
   #10; if(start_ready!==1 || cmd_valid!==0 || out_valid!==0 || done_valid!==0)
    $fatal(1,"ATTENTION_RESET_RESUMED");
   $display("ATTENTION_RESET_COMPLETE {reset}"); $finish;
  end
 end
end
always @(posedge clk) begin
 sample();
 if(rst_n) begin
  if(held_cmd && (!cmd_valid || cmd_addr!==held_addr)) $fatal(1,"ATTENTION_CMD_STALL");
  if(held_out && (!out_valid || {{out_data,out_index,out_last}}!==held_output))
   $fatal(1,"ATTENTION_OUT_STALL");
  if(held_done && (!done_valid || done_error!==4'd{3 if fault else 0}))
   $fatal(1,"ATTENTION_DONE_STALL");
  held_cmd=cmd_valid && !cmd_ready; held_addr=cmd_addr;
  held_out=out_valid && !out_ready; held_output={{out_data,out_index,out_last}};
  held_done=done_valid && !done_ready;
  if(held_cmd) reqstalls=reqstalls+1;
  if(pending && !result_valid) rspwait=rspwait+1;
  if(held_out) outstalls=outstalls+1;
  if(held_done) donestalls=donestalls+1;
  if(start_valid && start_ready) begin
   if(active) $fatal(1,"ATTENTION_DUPLICATE_START"); active=1;
  end
  if(result_valid && result_ready) begin
   if(!pending || cycles<=request_cycle) $fatal(1,"ATTENTION_RESPONSE");
   pending=0; responses=responses+1;
   if(result_error) retired_error=1;
  end
  if(retired_error && cmd_valid) $fatal(1,"ATTENTION_AFTER_ERROR");
  if(cmd_valid && cmd_ready) begin
   if(!active || pending || requests>={count} || cmd_addr!==addresses[requests])
    $fatal(1,"ATTENTION_REQUEST_ORDER %0d %h",requests,cmd_addr);
   request_cycle=cycles; response_cycle=cycles+3+requests%4; pending=1;
   result_data=words[requests]; result_error=requests=={error_at}; requests=requests+1;
  end
  if(out_valid) begin
   if({int(bool(fault))} || outputs>={dim} || out_index!==outputs ||
      out_last!==(outputs=={dim-1}) || out_data!==expected[outputs])
    $fatal(1,"ATTENTION_EXPECTED_OUTPUT %0d %h",outputs,out_data);
   if(out_ready) outputs=outputs+1;
  end
  if(done_valid && done_ready) begin
   if(pending || requests!={count} || responses!=requests ||
      outputs!={0 if fault else dim} || done_error!==4'd{3 if fault else 0} ||
      reqstalls==0 || rspwait==0 || donestalls<9 ||
      ({int(not fault)} && outstalls<8))
    $fatal(1,"ATTENTION_COMPLETION");
   $display("ATTENTION_COMPLETE %0d %0d %0d",requests,responses,outputs); $finish;
  end
 end
 #1; sample();
end
endmodule
"""
        tb = run.directory / (name+".sv")
        tb.write_text(text)
        executable = run.directory / (name+".vvp")
        run.receipt.setdefault("generated_source_sha256", {})[
            str(tb.relative_to(ROOT))] = hashlib.sha256(tb.read_bytes()).hexdigest()
        run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable,
                     *rtl_files(directory), tb], name+"-compile", timeout=5)
        out, _, _ = run.command(["vvp", executable], name+"-simulate", timeout=5)
        assert out.count("ATTENTION_RESET_COMPLETE " if reset else "ATTENTION_COMPLETE ") == 1
        record = {
            "case": name, "vision": vision, "full": full, "head": head,
            "kind": kind, "reset_phase": reset or None, "fault": fault,
            "expected_requests": count, "eligible_keys": eligible,
            "weighted_keys": weighted_keys, "expected_q40": expected,
            "public_samples_sha256": hashlib.sha256("\n".join(
                line for line in out.splitlines() if line.startswith("P ")).encode()).hexdigest(),
            "transcript": str((run.directory/(name+"-simulate.stdout")).relative_to(ROOT)),
        }
        summaries.append(record)
        run.receipt["coverage"].append(record)
        run.save()
    return summaries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--before-directory")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    directory = (ROOT / args.output).resolve()
    assert directory.is_relative_to(ROOT / "evidence/preparation")
    run = Run(directory, budget=100, repair_of=args.repair_of)
    run.receipt["related_evidence"] = [
        "evidence/preparation/q40-cursor-serial-paired-001/receipt.json",
        "evidence/preparation/q40-projection-attention-b17-001/receipt.json",
    ]
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
                "Every sampled public attention pin matches, including inactive values.")
    except Exception as error:
        (directory/"diagnostic.stderr").write_text(traceback.format_exc())
        run.finish("failed", str(error))
        traceback.print_exc()
        return 1
    run.finish("passed")
    print(json.dumps({"cases": len(run.receipt["coverage"]), "status": "passed"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
