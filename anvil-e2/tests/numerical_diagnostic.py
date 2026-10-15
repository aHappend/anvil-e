#!/usr/bin/env python3
"""Bounded oracle-only localization; never substitutes for admitted checks."""
import argparse
import copy
import dataclasses
import hashlib
import json
import math
from pathlib import Path
import sys
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Fixture, Floating, Integer, Q
from verify import ROOT, Run


OPERATORS = ("add", "mul", "mat", "mean", "norm", "scale", "gelu",
             "rotate", "attention")


def decoded(value):
    return [decoded(v) for v in value] if isinstance(value, list) else value/Q


def observed(base):
    def make_method(name):
        def method(self, *args, **kwargs):
            result = getattr(base, name)(self, *args, **kwargs)
            self.calls.append(copy.deepcopy({
                "operator": name, "args": args, "kwargs": kwargs,
                "result": result,
            }))
            return result
        return method
    cls = type("Observed"+base.__name__, (base,),
               {name: make_method(name) for name in OPERATORS})
    obj = cls()
    obj.calls = []
    return obj


class Checkpoints(dict):
    def __init__(self, ops):
        super().__init__()
        self.ops, self.boundaries = ops, {}

    def __setitem__(self, key, value):
        self.boundaries[key] = len(self.ops.calls)
        super().__setitem__(key, value)


def mathematical_args(call):
    name, args = call["operator"], list(call["args"])
    if name in ("scale", "rotate"):
        args[0] = decoded(args[0])
    elif name == "attention":
        args[:3] = [decoded(a) for a in args[:3]]
    else:
        args = [None if a is None else decoded(a) for a in args]
    return args


def operators(output, stage):
    fixture = Fixture(CONFIGS["B"], 89, 0)
    integer, floating = observed(Integer), observed(Floating)
    it, ft = Checkpoints(integer), Checkpoints(floating)
    fixture.run(integer, trace=it)
    fixture.run(floating, trace=ft)
    assert it.boundaries == ft.boundaries, "oracle operation paths differ"
    names = list(it)
    index = names.index(stage)
    assert index > 0
    start, end = it.boundaries[names[index-1]], it.boundaries[stage]
    records = []
    tensor_names = {}
    for name, value in fixture.tensors.items():
        if isinstance(value, dict):
            continue
        tensor_names[json.dumps(value)] = name
        matrix = fixture.matrix(name, Integer())
        tensor_names[json.dumps(matrix)] = name
    for number in range(start, end):
        ic, fc = integer.calls[number], floating.calls[number]
        assert ic["operator"] == fc["operator"]
        assert getattr(Integer(), ic["operator"])(*ic["args"], **ic["kwargs"]) == ic["result"], (
            f"mutable or invalid recorded operands at call {number}")
        args = mathematical_args(ic)
        matched = getattr(Floating(), ic["operator"])(*args, **ic["kwargs"])
        local = metrics(ic["result"], matched)
        total = metrics(ic["result"], fc["result"])
        propagated = max(abs(a-b) for a, b in
                         zip(flatten(matched), flatten(fc["result"])))
        input_metrics = metrics(ic["args"][0], fc["args"][0])
        if ic["operator"] == "mat":
            input_metrics = metrics(ic["args"][1], fc["args"][1])
        detail = {
            "input_metrics": input_metrics,
            "propagated_amplification": (
                propagated/input_metrics["max_abs_error"]
                if input_metrics["max_abs_error"] else None),
        }
        if ic["operator"] == "norm" and len(ic["args"]) > 1:
            detail["tensor"] = tensor_names.get(json.dumps(ic["args"][1]))
        elif ic["operator"] == "mat":
            detail["tensor"] = tensor_names.get(json.dumps(ic["args"][0]))
        if ic["operator"] == "norm":
            values = decoded(ic["args"][0])
            weighted = len(ic["args"]) > 1 and ic["args"][1] is not None
            detail["matched_denominator"] = math.sqrt(
                sum(v*v for v in values)/len(values) + 17/Q
                if weighted else sum(v*v for v in values))
        if ic["operator"] == "mat":
            weights, values = args
            detail["dot_cancellation_factors"] = [
                sum(abs(a*b) for a, b in zip(row, values))/abs(total)
                if total else None
                for row, total in zip(weights, matched)
            ]
        records.append({
            "call": number, "operator": ic["operator"],
            "integer_inputs_q24": ic["args"], "kwargs": ic["kwargs"],
            "mathematical_inputs": fc["args"],
            "integer_output_q24": ic["result"],
            "matched_input_mathematical_output": matched,
            "propagated_mathematical_output": fc["result"],
            "local_metrics": local, "total_metrics": total,
            "propagated_max_abs": propagated,
            **detail,
        })
    summaries = {}
    for name in OPERATORS:
        selected = [r for r in records if r["operator"] == name]
        if not selected:
            continue
        worst = max(selected, key=lambda r: r["total_metrics"]["max_abs_error"])
        summaries[name] = {
            "calls": len(selected),
            "max_local_error": max(r["local_metrics"]["max_abs_error"] for r in selected),
            "max_propagated_error": max(r["propagated_max_abs"] for r in selected),
            "max_total_error": worst["total_metrics"]["max_abs_error"],
            "worst_total_call": worst["call"],
            "worst_input_metrics": worst["input_metrics"],
            "worst_propagated_amplification": worst["propagated_amplification"],
        }
        if "matched_denominator" in worst:
            summaries[name]["worst_matched_denominator"] = worst["matched_denominator"]
        if "tensor" in worst:
            summaries[name]["worst_tensor"] = worst["tensor"]
        if name == "mat":
            factors = [v for r in selected for v in r["dot_cancellation_factors"]
                       if v is not None]
            summaries[name]["max_dot_cancellation_factor"] = max(factors)
        print(stage, name, json.dumps(summaries[name]), flush=True)
    output.write_text(json.dumps({
        "stage": stage, "seed": 89, "mode": 0,
        "previous_checkpoint": names[index-1],
        "checkpoint_metrics": metrics(it[stage], ft[stage]),
        "summaries": summaries, "calls": records,
    }, indent=2))


def retained_regression(run):
    original = json.loads((ROOT/run.receipt["repair_of"]).read_text())
    old = json.loads((ROOT/"evidence/preparation/b89-text-numerical-001/receipt.json").read_text())
    current = run.receipt["source_sha256"]
    matched_paths = [p for p in old["source_sha256"]
                     if p.startswith(("rtl/", "design/", "hf_embeddinggemma2_vision_spec/"))
                     or p == "tests/model.py"]
    for path in matched_paths:
        assert current[path] == old["source_sha256"][path], f"fixture source changed: {path}"
    fixture = Fixture(CONFIGS["B"], 89, 0)
    expected, writes = fixture.run(Integer())
    lines = (ROOT/"evidence/preparation/b89-text-numerical-001/"
             "B-seed89-text-simulate.stdout").read_text().splitlines()
    actual, actual_writes = [], {}
    for line in lines:
        parts = line.split()
        if parts and parts[0] == "E":
            assert int(parts[1]) == len(actual)
            assert int(parts[3]) == (len(actual) == fixture.dimension-1)
            value = int(parts[2], 16)
            actual.append(value - (1 << 32) if value & (1 << 31) else value)
        elif parts and parts[0] == "W":
            actual_writes.setdefault(int(parts[1], 16), []).append(int(parts[2], 16))
    assert actual == expected and actual_writes == writes
    mathematical, _ = fixture.run(Floating())
    error = max(abs(a/Q-b) for a, b in zip(actual, mathematical))
    assert error > 0.002 and abs(error-0.0023715018597183155) < 1e-14
    run.receipt["assertions"].append({
        "retained_not_rerun": True, "unchanged_source_paths": matched_paths,
        "original_simulation_receipt": "evidence/preparation/b89-text-numerical-001/receipt.json",
        "compared_output_components": len(actual),
        "compared_scratch_addresses": len(writes),
        "mathematical_error": error, "unchanged_threshold": 0.002,
        "mathematical_acceptance": False,
        "prior_diagnostic_status": original["status"],
    })


def norm_probe(run, data):
    """Public norm pins on the most amplified independently derived operands."""
    candidates = [c for c in data["calls"] if c["operator"] == "norm"]
    case = max(candidates, key=lambda c: c["total_metrics"]["max_abs_error"])
    values, weights = case["integer_inputs_q24"]
    expected = case["integer_output_q24"]
    count = len(values)
    assert count == len(weights) == len(expected)
    loads = "\n".join(
        f"values[{i}]=32'h{x & 0xffffffff:08x}; "
        f"weights[{i}]=32'h{w & 0xffffffff:08x}; "
        f"expected[{i}]=32'h{e & 0xffffffff:08x};"
        for i, (x, w, e) in enumerate(zip(values, weights, expected)))
    bench = f"""
module tb;
reg clk=0,rst_n=0,start_valid=0,in_valid=0,out_ready=0;
always #5 clk=~clk;
wire start_ready,in_ready,out_valid,out_last,out_error;
wire signed [31:0] out_data;
wire [31:0] out_index;
reg signed [31:0] in_data=0,in_weight=0;
reg signed [31:0] values[0:{count-1}],weights[0:{count-1}],expected[0:{count-1}];
integer cycles=0,loaded=0,beats=0,stalls=0;
reg started=0,held=0;
reg [65:0] held_payload;
anvil_e2_norm #(.MAX_WIDTH({count})) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_count(32'd{count}),.start_l2(1'b0),.in_valid(in_valid),.in_ready(in_ready),
 .in_data(in_data),.in_weight(in_weight),.out_valid(out_valid),.out_ready(out_ready),
 .out_data(out_data),.out_index(out_index),.out_last(out_last),.out_error(out_error));
task automatic known;
begin
 if ((^{{start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error}})===1'bx)
  $fatal(1,"NORM_UNKNOWN");
 if (!rst_n && {{start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error}}!=='0)
  $fatal(1,"NORM_RESET");
end
endtask
initial begin
 {loads}
 #0;known();#1;known();#11;rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1;
  if(cycles>1000) $fatal(1,"NORM_TIMEOUT");
  start_valid=!started;
  in_valid=started && loaded<{count};
  if(loaded<{count}) begin in_data=values[loaded];in_weight=weights[loaded];end
  out_ready=cycles%5==0;
 end
end
always @(posedge clk) begin
 known();
 if(rst_n) begin
  if(start_valid && start_ready) started=1;
  if(in_valid && in_ready) loaded=loaded+1;
  if(held && (!out_valid || {{out_data,out_index,out_last,out_error}}!==held_payload))
   $fatal(1,"NORM_STABILITY");
  held=out_valid && !out_ready;
  held_payload={{out_data,out_index,out_last,out_error}};
  if(held) stalls=stalls+1;
  if(out_valid && out_ready) begin
   if(beats>={count} || out_index!==32'(beats) || out_data!==expected[beats] ||
      out_last!==(beats=={count-1}) || out_error!==0) $fatal(1,"NORM_MISMATCH");
   $display("N %0d %h",out_index,out_data);
   beats=beats+1;
   if(beats=={count}) begin
    if(loaded!={count} || stalls==0) $fatal(1,"NORM_COVERAGE");
    $display("NORM_COMPLETE %0d %0d",beats,stalls);$finish;
   end
  end
 end
end
endmodule
"""
    run.tools(("iverilog", "vvp"))
    tb, executable = run.directory/"matched-norm.sv", run.directory/"matched-norm.vvp"
    tb.write_text(bench)
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable,
                 ROOT/"rtl/anvil_e2_norm.sv", tb], "matched-norm-compile", timeout=5)
    out, _, _ = run.command(["vvp", executable], "matched-norm-simulate", timeout=5)
    lines = [line.split() for line in out.splitlines() if line.startswith("N ")]
    actual = [int(line[2], 16) for line in lines]
    assert [int(line[1]) for line in lines] == list(range(count))
    assert actual == [e & 0xffffffff for e in expected]
    assert out.count("NORM_COMPLETE ") == 1
    run.receipt["assertions"].append({
        "case": "matched-public-norm", "tensor": case["tensor"],
        "input_q24": values, "weight_q24": weights, "output_q24": expected,
        "matched_mathematical_output": case["matched_input_mathematical_output"],
        "propagated_mathematical_output": case["propagated_mathematical_output"],
        "local_error": case["local_metrics"]["max_abs_error"],
        "propagated_error": case["propagated_max_abs"],
        "component_comparisons": len(actual),
        "scope": "operator diagnostic, not end-to-end acceptance",
    })


def flatten(values):
    if isinstance(values, list):
        return [v for row in values for v in flatten(row)]
    return [values]


def metrics(integer, floating):
    a, b = flatten(integer), flatten(floating)
    assert len(a) == len(b) and a
    errors = [abs(x/Q-y) for x, y in zip(a, b)]
    return {
        "components": len(a), "max_abs_error": max(errors),
        "error_l2": math.sqrt(sum(e*e for e in errors)),
        "integer_l2": math.sqrt(sum((x/Q)**2 for x in a)),
        "floating_l2": math.sqrt(sum(y*y for y in b)),
        "integer_max_abs": max(abs(x/Q) for x in a),
        "floating_max_abs": max(abs(y) for y in b),
    }


def vector_metrics(integer, floating, path=()):
    if not isinstance(integer[0], list):
        return [{"path": list(path), **metrics(integer, floating)}]
    return [entry for i, (a, b) in enumerate(zip(integer, floating))
            for entry in vector_metrics(a, b, path+(i,))]


def traces(output):
    fixture = Fixture(CONFIGS["B"], 89, 0)
    integer, floating = {}, {}
    fixture.run(Integer(), trace=integer)
    fixture.run(Floating(), trace=floating)
    assert list(integer) == list(floating)
    assert list(integer) == [
        "fusion", "cached_ple", *[f"text.{i}" for i in range(6)],
        "projected", "pooled", "output",
    ]
    summaries = {}
    previous = None
    for name in integer:
        summary = metrics(integer[name], floating[name])
        summary["vectors"] = vector_metrics(integer[name], floating[name])
        summary["max_error_amplification_from_previous_checkpoint"] = (
            summary["max_abs_error"]/previous if previous else None)
        previous = summary["max_abs_error"]
        summaries[name] = summary
        print(name, json.dumps(summary), flush=True)
    assert abs(summaries["output"]["max_abs_error"] -
               0.0023715018597183155) < 1e-14, "changed failing fixture"
    result = {
        "config": dataclasses.asdict(fixture.c), "seed": 89, "mode": 0,
        "dimension": fixture.dimension, "threshold": 0.002,
        "integer_q24": integer, "mathematical": floating, "summaries": summaries,
    }
    output.write_text(json.dumps(result, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--child-output")
    parser.add_argument("--stage")
    parser.add_argument("--norm-probe", action="store_true")
    parser.add_argument("--repair-of",
                        default="evidence/preparation/b89-text-numerical-001/receipt.json")
    args = parser.parse_args()
    if args.child_output:
        if args.stage:
            operators(Path(args.child_output), args.stage)
        else:
            traces(Path(args.child_output))
        return
    run = Run(args.directory, budget=25, repair_of=args.repair_of)
    try:
        run.tools(("python3",))
        retained_regression(run)
        snapshot = run.directory/"probe.py"
        snapshot.write_bytes(Path(__file__).read_bytes())
        run.receipt["probe_source"] = {
            "path": str(snapshot.relative_to(ROOT)),
            "sha256": hashlib.sha256(snapshot.read_bytes()).hexdigest(),
        }
        label = "matched-operators" if args.stage else "paired-traces"
        result = run.directory/(label+".json")
        command = [sys.executable, Path(__file__).resolve(),
                   "--directory", run.directory, "--child-output", result]
        if args.stage:
            command += ["--stage", args.stage]
        run.command(command, label, timeout=15)
        data = json.loads(result.read_text())
        if args.norm_probe:
            norm_probe(run, data)
        run.receipt["assertions"].append({
            "diagnostic_result": data["summaries"],
            "diagnostic_only": True, "acceptance": False,
        })
        run.finish("passed")
    except Exception as error:
        run.finish("failed", str(error))
        traceback.print_exc()
        raise


if __name__ == "__main__":
    main()
