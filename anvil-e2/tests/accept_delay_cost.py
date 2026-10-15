"""Diagnostic-only descriptor-acceptance delayed-work scheduling comparison."""
import argparse
import dataclasses
import hashlib
import json
import re
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Fixture, Floating, Integer, Q, SCRATCH
from monitor_cost import (changes, memory_file, observations, records, simulate,
                          stall_coverage, writes_checked)
from progress import monitored_prefix
from verify import ROOT, Run, bench


def candidate(text, recorded=False):
    capture = " capture();" if recorded else ""
    before = f"""  #1;{capture}
  if(active) job_valid=0;
  if(cycles==accept_cycle && (busy!==1 || job_ready!==0 || mem_req_valid!==0))
    $fatal(1,"POST_ACCEPT");"""
    after = f"""  if(cycles==accept_cycle) begin
   #1;{capture}
   if(active) job_valid=0;
   if(busy!==1 || job_ready!==0 || mem_req_valid!==0)
    $fatal(1,"POST_ACCEPT");
  end"""
    if recorded:
        # Retain the baseline's every-edge observation, separately from the
        # candidate work. These instrumented arms are not timing measurements.
        after += "\n  else begin #1; capture(); end"
    assert text.count(before) == 1, "trailing delayed-work replacement not unique"
    result = text.replace(before, after)
    assert result.replace(after, before) == text
    return result


def prepare(text, folder, recorded, limit=100000, boundary=False):
    text = monitored_prefix(observations(text), folder, limit, baseline=not recorded)
    if boundary:
        assert recorded
        text = text.replace("endmodule", f"""
final begin
 $writememh("{folder / 'public-samples.mem'}",samples,0,record_count-1);
 $display("BOUNDARY_SAMPLES %0d %0d",sample_count,record_count);
end
endmodule
""")
    return text


def exact_samples(run, left, right):
    a = changes(run.directory/left/"public-samples.mem")
    b = changes(run.directory/right/"public-samples.mem")
    assert a == b, "sampled public/host values or timestamps differ"
    return len(a)


def cost_record(run, names):
    result = {}
    for name in names:
        execution = next(e for e in run.receipt["executions"]
                         if e["stdout"].endswith(name+"-simulate.stdout"))
        result[name] = {key: execution[key] for key in (
            "elapsed_s", "child_user_cpu_s", "child_system_cpu_s")}
        result[name]["events"] = run.receipt["measurements"][name]["events"]
    return result


def retained_prefix(run, relative):
    directory = (ROOT/relative).resolve()
    assert directory.is_relative_to(ROOT/"evidence/preparation")
    path = directory/"receipt.json"
    receipt = json.loads(path.read_text())
    assert receipt["status"] == "failed"
    assert all(receipt["source_sha256"][name] == digest
               for name, digest in run.receipt["source_sha256"].items()
               if name != "tests/accept_delay_cost.py"), "retained input identity"
    run.receipt["retained_prefix"] = str(path.relative_to(ROOT))
    paths = [path]
    fixture = Fixture(CONFIGS["B"], 17, 2)
    integer, expected = fixture.run(Integer())
    floating, _ = fixture.run(Floating())
    assert max(abs(a/Q-b) for a, b in zip(integer, floating)) <= .002
    assert abs(sum((a/Q)**2 for a in integer)**.5-1) <= .002
    memory = directory/"input.mem"
    assert memory.read_text() == "".join(
        f"{a:016x} {v & 0xffffffff:08x}\n" for a, v in sorted(fixture.mem.items()))
    paths.append(memory)
    original = bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4)
    outputs = {}
    for name in receipt["cost_comparison"]["arms"]:
        recorded = name.endswith("recorded")
        text = prepare(original, directory/name, recorded)
        if name.startswith("candidate"):
            text = candidate(text, recorded)
        tb = directory/name/"tb.sv"
        assert tb.read_text() == text, "retained generated bench identity"
        assert hashlib.sha256(tb.read_bytes()).hexdigest() == receipt[
            "generated_source_sha256"][str(tb.relative_to(ROOT))]
        stdout, stderr = (directory/(name+"-simulate."+suffix)
                          for suffix in ("stdout", "stderr"))
        outputs[name] = stdout.read_text()
        assert outputs[name].count("DIAGNOSTIC_STOP_INCOMPLETE") == 1
        assert "TRANSCRIPT_COMPLETE" not in outputs[name]
        writes_checked(outputs[name], expected)
        events = {kind: int(count) for count, kind in re.findall(
            r"^\s*(\d+)\s+(thread schedule events|assign events|other events)(?:\s|$)",
            outputs[name]+"\n"+stderr.read_text(), re.M)}
        assert events == receipt["cost_comparison"]["arms"][name]["events"]
        execution = next(e for e in receipt["executions"]
                         if e["stdout"].endswith(name+"-simulate.stdout"))
        assert execution["exit_code"] == 0 and not execution["timed_out"]
        paths.extend((tb, stdout, stderr))
    baseline = outputs["baseline-recorded"]
    assert records(baseline) == records(outputs["candidate-recorded"])
    traffic = lambda s: [line for line in s.splitlines()
                         if line.startswith(("T ", "R ", "W ", "PROGRESS ",
                                             "DIAGNOSTIC_STOP_"))]
    assert all(traffic(s) == traffic(baseline) for s in outputs.values())
    a, b = (directory/name/"public-samples.mem"
            for name in ("baseline-recorded", "candidate-recorded"))
    assert changes(a) == changes(b)
    paths.extend((a, b))
    assert int(re.search(r"^SAMPLES (\d+)$", baseline, re.M)[1]) == 300004
    run.receipt["retained_artifact_sha256"] = {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in paths}
    run.receipt["assertions"].append({
        "retained_prefix_reanalysis": True, "sampled_public_host_observations_exact": 300004,
        "change_records_exact": len(changes(a)),
        "request_records": sum(s.startswith("T ") for s in baseline.splitlines()),
        "response_records": sum(s.startswith("R ") for s in baseline.splitlines()),
        "independent_prefix_writes": writes_checked(baseline, expected),
        "all_six_arms_traffic_exact": True,
        "generated_sources_reconstructed_exactly": True})
    run.receipt["cost_comparison"] = receipt["cost_comparison"]
    run.receipt["candidate"] = receipt["candidate"]
    run.save()


def prefix(run):
    run.receipt["candidate"] = {
        "diagnostic_only": True, "adopted": False, "production_changed": False,
        "delta": "Gate only the trailing posedge #1/deassert/POST_ACCEPT work "
                 "on cycles==accept_cycle (set only by actual descriptor acceptance).",
        "unchanged": "Completion-edge #1, known/reset observations, responder, "
                     "stalls, errors, clock, fixture, oracle and child watchdogs.",
        "recording_overhead": "Recorded candidate retains the every-edge delayed "
                              "capture as observation-only work; excluded from timing arms.",
        "decision_rule": "Both AB/BA unrecorded arms must improve elapsed time by "
                         "at least 15%; complete serial B17/C89 comparisons required "
                         "before adoption. Prefix speedup alone is not acceptance."}
    fixture = Fixture(CONFIGS["B"], 17, 2)
    integer, expected = fixture.run(Integer())
    floating, _ = fixture.run(Floating())
    absolute = max(abs(a/Q-b) for a, b in zip(integer, floating))
    norm = abs(sum((a/Q)**2 for a in integer)**0.5-1)
    assert absolute <= .002 and norm <= .002
    run.receipt["fixture"] = {
        "configuration": dataclasses.asdict(fixture.c), "seed": 17, "mode": 2,
        "prefix_cycles": 100000, "mathematical_max_abs_error": absolute,
        "l2_error": norm, "complete_fixture": False}
    memory = memory_file(run, fixture, "input")
    original = bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4)
    outputs, elapsed = {}, {}
    arms = (("baseline-recorded", False, True), ("candidate-recorded", True, True),
            ("baseline-timing-1", False, False), ("candidate-timing-1", True, False),
            ("candidate-timing-2", True, False), ("baseline-timing-2", False, False))
    for name, changed, recorded in arms:
        text = prepare(original, run.directory/name, recorded)
        if changed:
            text = candidate(text, recorded)
        outputs[name], elapsed[name] = simulate(run, name, text)
        assert outputs[name].count("DIAGNOSTIC_STOP_INCOMPLETE") == 1
        assert "TRANSCRIPT_COMPLETE" not in outputs[name]
        writes_checked(outputs[name], expected)
    baseline = outputs["baseline-recorded"]
    assert records(baseline) == records(outputs["candidate-recorded"])
    nchanges = exact_samples(run, "baseline-recorded", "candidate-recorded")
    nsamples = int(re.search(r"^SAMPLES (\d+)$", baseline, re.M)[1])
    assert nsamples == 300004
    traffic = lambda s: [line for line in s.splitlines()
                         if line.startswith(("T ", "R ", "W ", "PROGRESS ",
                                             "DIAGNOSTIC_STOP_"))]
    assert all(traffic(s) == traffic(baseline) for s in outputs.values())
    run.receipt["assertions"].append({
        "sampled_public_host_observations_exact": nsamples,
        "change_records_exact": nchanges,
        "request_records": sum(s.startswith("T ") for s in baseline.splitlines()),
        "response_records": sum(s.startswith("R ") for s in baseline.splitlines()),
        "independent_prefix_writes": writes_checked(baseline, expected),
        "all_six_arms_traffic_exact": True})
    ratios = [elapsed[f"candidate-timing-{i}"]/elapsed[f"baseline-timing-{i}"]
              for i in (1, 2)]
    run.receipt["cost_comparison"] = {
        "arms": cost_record(run, [name for name, _, _ in arms]),
        "candidate_over_baseline": ratios,
        "useful_prefix_headroom": all(r <= .85 for r in ratios),
        "adopted": False,
        "limitation": "Incomplete prefix; no aggregate budget compliance or "
                      "causal dominant-cost attribution."}
    run.save()
    boundaries(run)


def boundaries(run):
    fixture = Fixture(CONFIGS["A"], 17, 0)
    integer, scratch = fixture.run(Integer())
    memory = memory_file(run, fixture, "boundary-input")
    cases = ("completion", "back-to-back", "request", "response", "output", "done")
    for phase in cases:
        jobs = 2 if phase == "back-to-back" else 1
        reset = phase if phase in ("request", "response", "output") else (
            "output" if phase == "done" else None)
        original = stall_coverage(bench(
            fixture, memory, (fixture.layout["end"]-SCRATCH)//4,
            reset_phase=reset, jobs=jobs))
        if phase in ("request", "output", "done"):
            old = "mem_req_valid && !mem_req_ready" if phase == "request" else (
                "emb_valid && !emb_ready")
            flag, count = {"request": ("stalled_request", "req_hold"),
                           "output": ("stalled_embedding", "emb_hold"),
                           "done": ("stalled_done", "done_hold")}[phase]
            before = f"  if({old} && !reset_done) begin"
            assert original.count(before) == 1
            original = original.replace(
                before, f"  if({flag} && {count}>=2 && !reset_done) begin")
            if phase == "done":
                original = original.replace("RESET_OBSERVED output", "RESET_OBSERVED done")
        # Log acceptance and post-delay events without affecting any pins.
        original = original.replace("   accept_cycle=cycles; active=1;",
                                    '   accept_cycle=cycles; active=1;\n'
                                    '   $display("J %0d %0t",cycles,$time);')
        arms = []
        expected = {a: v*jobs for a, v in scratch.items()}
        for changed in (False, True):
            name = f"boundary-{phase}-{'candidate' if changed else 'baseline'}"
            text = prepare(original, run.directory/name, True, limit=100000,
                           boundary=True)
            if changed:
                text = candidate(text, True)
            out, _ = simulate(run, name, text)
            complete = phase in ("completion", "back-to-back", "done")
            if phase == "response":
                # This reset is before the first response, hence before any
                # scratch write. The generic prefix helper requires a write.
                assert not any(s.startswith("W ") for s in out.splitlines())
                assert any(s.startswith("T ") for s in out.splitlines())
            else:
                writes_checked(out, expected, complete=complete)
            if reset:
                assert f"RESET_OBSERVED {phase}" in out and "RESET_COMPLETE" in out
            else:
                assert out.count("TRANSCRIPT_COMPLETE") == 1
                assert sum(s.startswith("C ") for s in out.splitlines()) == jobs
                beats = [int(s.split()[2], 16) for s in out.splitlines()
                         if s.startswith("E ")]
                assert beats == [v & 0xffffffff for v in integer]*jobs
            assert sum(s.startswith("J ") for s in out.splitlines()) == jobs
            coverage = [list(map(int, s.split()[1:])) for s in out.splitlines()
                        if s.startswith("STALL_COVERAGE ")]
            assert coverage
            if phase in ("completion", "back-to-back"):
                assert all(v > 0 for v in coverage[-1])
            if phase in ("request", "output", "done"):
                offset = {"request": 0, "output": 3, "done": 6}[phase]
                assert coverage[-1][offset] > 0 and coverage[-1][offset+1] >= 2
            arms.append((name, out))
        assert records(arms[0][1]) == records(arms[1][1])
        assert [s for s in arms[0][1].splitlines() if s.startswith("J ")] == [
            s for s in arms[1][1].splitlines() if s.startswith("J ")]
        nchanges = exact_samples(run, arms[0][0], arms[1][0])
        run.receipt["coverage"].append({
            "boundary": phase, "jobs": jobs, "exact_public_host_changes": nchanges,
            "acceptance_times_exact": True, "scratch_independent": True,
            "stall_counts": coverage[-1]})
        run.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--retained-prefix")
    args = parser.parse_args()
    run = Run(ROOT/args.output, budget=110, repair_of=(
        args.retained_prefix+"/receipt.json" if args.retained_prefix else
        "evidence/preparation/q40-response-edge-aggregate-cost-001/receipt.json"))
    try:
        run.tools(("python3", "iverilog", "vvp"))
        if args.retained_prefix:
            retained_prefix(run, args.retained_prefix)
            boundaries(run)
        else:
            prefix(run)
        run.finish("diagnostic-complete")
    except Exception as error:
        run.receipt["traceback"] = traceback.format_exc()
        run.finish("failed", str(error))
        raise
    print(json.dumps({"receipt": args.output+"/receipt.json",
                      "cost_comparison": run.receipt["cost_comparison"]}))


if __name__ == "__main__":
    main()
