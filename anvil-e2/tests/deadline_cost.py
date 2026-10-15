"""Bounded watchdog proof and serial cost measurement; advisory, not acceptance."""
import time

ENTRY_MONOTONIC = time.monotonic()
ENTRY_PYTHON_CPU = time.process_time()

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Fixture
from scheduler_cost import capacity
from verify import ROOT, Run, execute_fixture

AGGREGATE = "evidence/preparation/q40-response-edge-aggregate-cost-001/receipt.json"


class CostRun(Run):
    def command(self, argv, name, **kwargs):
        if name.endswith("-compile"):
            tb = Path(argv[-1])
            text = tb.read_text()
            marker = '   $display("C %0d'
            assert text.count(marker) == 1
            text = text.replace(marker, '''   $display("DIAGNOSTIC_COUNTS %0d %0d %0d",
     cycles,requests,responses);
''' + marker)
            marker = "endmodule"
            assert text.count(marker) == 1
            text = text.replace(marker, """
always @(posedge clk) if(cycles>0 && cycles%10000==0) begin
 $display("DIAGNOSTIC_PROGRESS %0d %0d %0d",cycles,requests,responses);
 $fflush();
end
endmodule
""")
            tb.write_text(text)
            self.receipt.setdefault("generated_source_sha256", {})[
                str(tb.relative_to(ROOT))] = hashlib.sha256(tb.read_bytes()).hexdigest()
            self.save()
        return super().command(argv, name, **kwargs)


def watchdog(run):
    run.tools(("python3",))
    for name, budget, requested in (("child-limit", 4, 0.4),
                                    ("common-limit", 0.4, 4)):
        child = Run(run.directory/name, budget=budget, deadline=run.deadline,
                    repair_of=AGGREGATE)
        child.receipt["tools"] = run.receipt["tools"]
        child.save()
        code = ("import os,sys,time; "
                "print('FLUSHED_STDOUT',os.getpid(),flush=True); "
                "print('FLUSHED_STDERR',file=sys.stderr,flush=True); "
                "time.sleep(30)")
        try:
            child.command([sys.executable, "-c", code], name, timeout=requested)
        except AssertionError as error:
            record = child.receipt["executions"][-1]
            assert str(error) == f"tool timeout: {name}"
            assert record["timed_out"] and record["exit_code"] != 0
            assert record["cleanup"]["direct_child_reaped"]
            assert record["effective_timeout_s"] <= requested
            if name == "child-limit":
                assert record["effective_timeout_s"] == requested
            else:
                assert 0 < record["effective_timeout_s"] < requested
            assert record["elapsed_s"] < record["effective_timeout_s"]+1
            out = (ROOT/record["stdout"]).read_text()
            err = (ROOT/record["stderr"]).read_text()
            assert out.startswith("FLUSHED_STDOUT ") and err == "FLUSHED_STDERR\n"
            pid = int(out.split()[1])
            assert pid == record["pid"]
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError(f"child still exists: {pid}")
            child.receipt["assertions"].append(
                "binding watchdog timed out; direct child absent/reaped; both flushed outputs retained")
            child.finish("expected-timeout")
        else:
            child.finish("failed", "overlong child unexpectedly completed")
            raise AssertionError("watchdog failed to interrupt overlong child")
        run.receipt["coverage"].append({
            "case": name, "receipt": str((child.directory/"receipt.json").relative_to(ROOT)),
            "requested_timeout_s": requested,
            "effective_timeout_s": record["effective_timeout_s"],
            "elapsed_s": record["elapsed_s"], "timeout_cleanup_and_partial_output": True})
        run.save()
    assert len(run.receipt["coverage"]) == 2


def observations(run, name):
    path = run.directory/(name+"-simulate.stdout")
    if not path.exists():
        return {"simulation_launched": False}
    lines = path.read_bytes().splitlines(keepends=True)
    result = {"simulation_launched": True, "complete": False,
              "complete_write_records": 0, "embedding_records": 0,
              "last_observed_cycles_requests_responses": None,
              "partial_final_line": bool(lines and not lines[-1].endswith(b"\n"))}
    for line in lines:
        if not line.endswith(b"\n"):
            continue
        fields = line.split()
        if fields and fields[0] in (b"DIAGNOSTIC_PROGRESS", b"DIAGNOSTIC_COUNTS"):
            result["last_observed_cycles_requests_responses"] = list(map(int, fields[1:]))
        elif fields and fields[0] == b"W":
            result["complete_write_records"] += 1
        elif fields and fields[0] == b"E":
            result["embedding_records"] += 1
        elif line.strip() == b"TRANSCRIPT_COMPLETE":
            result["complete"] = True
    return result


def serial(run):
    run.tools(("python3", "iverilog", "vvp"))
    run.receipt["capacity_before"] = capacity()
    run.save()
    for label, seed in (("B", 17), ("C", 89)):
        name = f"{label}-s{seed}-m2-d12"
        began = time.monotonic(), time.process_time()
        fixture = Fixture(CONFIGS[label], seed, 2)
        run.timing(name+"-fixture-setup", began)
        child = CostRun(run.directory/name, deadline=run.deadline, repair_of=AGGREGATE)
        child.receipt["tools"] = run.receipt["tools"]
        child.save()
        began = time.monotonic(), time.process_time()
        try:
            execute_fixture(child, name, fixture)
            counts = observations(child, name)
            coverage = child.receipt["coverage"][0]
            assert counts["complete"]
            assert counts["last_observed_cycles_requests_responses"][1:] == coverage["completion"][1:3]
            assert counts["embedding_records"] == coverage["compared_components"]
        except Exception as error:
            child.receipt["public_observations"] = observations(child, name)
            child.finish("failed", str(error))
            raise
        else:
            child.receipt["public_observations"] = counts
            child.finish("passed")
            run.receipt["coverage"].extend(child.receipt["coverage"])
        finally:
            run.receipt.setdefault("case_costs", []).append({
                "case": name, "elapsed_s": time.monotonic()-began[0],
                "python_cpu_s": time.process_time()-began[1],
                "receipt": str((child.directory/"receipt.json").relative_to(ROOT)),
                "status": child.receipt["status"],
                "observations": child.receipt["public_observations"]})
            run.save()
    assert len(run.receipt["coverage"]) == 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", choices=("watchdog", "serial"), required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--watchdog-receipt")
    args = parser.parse_args()
    directory = (ROOT/args.output).resolve()
    assert directory.is_relative_to(ROOT/"evidence/preparation")
    budget = 12 if args.check == "watchdog" else 100
    run = Run(directory, budget=budget, deadline=ENTRY_MONOTONIC+budget,
              repair_of=AGGREGATE)
    run.receipt["diagnostic_scope"] = {
        "acceptance_evidence": False, "absolute_budget_s": budget,
        "entry_monotonic": ENTRY_MONOTONIC,
        "predicate_candidate_adopted": False, "concurrency_adopted": False,
        "shared_throttling_deltas": "nonexclusive; not causal DUT CPU attribution",
        "planned_cases": (["child-limit", "common-limit"] if args.check == "watchdog"
                          else [["B", 17, 2], ["C", 89, 2]])}
    run.save()
    try:
        if args.check == "serial":
            assert args.watchdog_receipt, "watchdog proof required before measurement"
            path = (ROOT/args.watchdog_receipt).resolve()
            assert path.is_relative_to(ROOT/"evidence/preparation")
            receipt = json.loads(path.read_text())
            assert receipt["status"] == "passed" and len(receipt["coverage"]) == 2
            assert receipt["source_sha256"] == run.receipt["source_sha256"]
            run.receipt["watchdog_receipt"] = {
                "path": str(path.relative_to(ROOT)),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            serial(run)
        else:
            watchdog(run)
        assert time.monotonic() < run.deadline, "absolute diagnostic deadline exceeded"
    except Exception as error:
        (directory/"diagnostic.stderr").write_text(traceback.format_exc())
        run.finish("failed", str(error))
        status = 1
    else:
        run.finish("passed")
        status = 0
    run.receipt["capacity_after"] = capacity()
    run.receipt["total_entry_elapsed_s"] = time.monotonic()-ENTRY_MONOTONIC
    run.receipt["total_entry_python_cpu_s"] = time.process_time()-ENTRY_PYTHON_CPU
    run.save()
    print(json.dumps({"status": run.receipt["status"],
                      "receipt": str((directory/"receipt.json").relative_to(ROOT)),
                      "elapsed_s": run.receipt["total_entry_elapsed_s"]}))
    return status


if __name__ == "__main__":
    sys.exit(main())
