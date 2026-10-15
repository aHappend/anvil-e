"""Advisory real-DUT comparison of conditional held-payload capture only."""
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
from progress import monitored_prefix
from verify import ROOT, Run, bench, rtl_files


def conditional_capture(text):
    replacements = (
        ("  held_request={mem_req_write,mem_req_addr,mem_req_wdata};",
         "  if(stalled_request) held_request={mem_req_write,mem_req_addr,mem_req_wdata};"),
        ("  held_embedding={emb_data,emb_index,emb_last};",
         "  if(stalled_embedding) held_embedding={emb_data,emb_index,emb_last};"),
        ("  stalled_done=done_valid && !done_ready; held_error=done_error;",
         "  stalled_done=done_valid && !done_ready; if(stalled_done) held_error=done_error;"),
    )
    original = text
    for before, after in replacements:
        assert text.count(before) == 1, "capture replacement not unique"
        text = text.replace(before, after)
    restored = text
    for before, after in reversed(replacements):
        restored = restored.replace(after, before)
    assert restored == original, "unexpected diagnostic delta"
    return text


def observations(text):
    marker = "  if(mem_rsp_valid && mem_rsp_ready) begin"
    assert text.count(marker) == 1
    return text.replace(marker, marker + """
   $display("R %0d %h %b",cycles,mem_rsp_rdata,mem_rsp_error);""")


def stall_coverage(text):
    declarations = """
integer req_entry=0,req_hold=0,req_release=0;
integer emb_entry=0,emb_hold=0,emb_release=0;
integer done_entry=0,done_hold=0,done_release=0;
always @(negedge rst_n) begin
 stalled_request=0; stalled_embedding=0; stalled_done=0;
end
"""
    text = text.replace("task automatic known;", declarations + "\ntask automatic known;")
    marker = "  stalled_request=mem_req_valid && !mem_req_ready;"
    coverage = ""
    for prefix, flag, valid, ready in (
            ("req", "stalled_request", "mem_req_valid", "mem_req_ready"),
            ("emb", "stalled_embedding", "emb_valid", "emb_ready"),
            ("done", "stalled_done", "done_valid", "done_ready")):
        coverage += f"""
  if({valid} && !{ready}) begin
   if({flag}) {prefix}_hold={prefix}_hold+1;
   else {prefix}_entry={prefix}_entry+1;
  end
  if({flag} && {valid} && {ready}) {prefix}_release={prefix}_release+1;
"""
    assert text.count(marker) == 1
    text = text.replace(marker, coverage + marker)
    report = """
   $display("STALL_COVERAGE %0d %0d %0d %0d %0d %0d %0d %0d %0d",
     req_entry,req_hold,req_release,emb_entry,emb_hold,emb_release,
     done_entry,done_hold,done_release);
"""
    text = text.replace('   $display("RESET_OBSERVED', report + '   $display("RESET_OBSERVED')
    text = text.replace('    $display("TRANSCRIPT_COMPLETE");',
                        report + '    $display("TRANSCRIPT_COMPLETE");')
    return text


def memory_file(run, fixture, name):
    path = run.directory / (name + ".mem")
    path.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                            for a, v in sorted(fixture.mem.items())))
    return path


def writes_checked(out, expected, complete=False):
    observed = {}
    for line in out.splitlines():
        fields = line.split()
        if fields and fields[0] == "W":
            observed.setdefault(int(fields[1], 16), []).append(int(fields[2], 16))
    if complete:
        assert observed == expected, "complete independent scratch history"
    else:
        assert observed and all(a in expected and v == expected[a][:len(v)]
                                for a, v in observed.items()), "independent scratch prefix"
    return sum(map(len, observed.values()))


def records(out):
    return [line for line in out.splitlines()
            if line.startswith(("T ", "R ", "W ", "E ", "C ", "PROGRESS ",
                                "SAMPLES ", "CHANGES ", "DIAGNOSTIC_STOP_",
                                "RESET_", "STALL_COVERAGE ", "TRANSCRIPT_COMPLETE"))]


def changes(path):
    return [int(line, 16) for line in path.read_text().splitlines()
            if line and not line.startswith("//")]


def simulate(run, name, text):
    folder = run.directory / name
    folder.mkdir()
    tb, exe = folder / "tb.sv", folder / "tb.vvp"
    tb.write_text(text)
    run.receipt.setdefault("generated_source_sha256", {})[
        str(tb.relative_to(ROOT))] = hashlib.sha256(tb.read_bytes()).hexdigest()
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", exe,
                 *rtl_files(), tb], name + "-compile", timeout=10)
    start = time.monotonic()
    out, err, _ = run.command(["vvp", "-v", exe], name + "-simulate", timeout=30)
    elapsed = time.monotonic() - start
    events = {kind: int(count) for count, kind in re.findall(
        r"^\s*(\d+)\s+(thread schedule events|assign events|other events)(?:\s|$)",
        out + "\n" + err, re.M)}
    assert len(events) == 3, "missing simulator event counts"
    run.receipt.setdefault("measurements", {})[name] = {
        "simulation_s": elapsed, "events": events}
    run.save()
    return out, elapsed


def probe(run, retained_prefix=None):
    reference = ROOT / "evidence/preparation/q40-current-monitored-host-b17-007/receipt.json"
    current = ROOT / "evidence/preparation/q40-attention-cursor-c89-paired-002/receipt.json"
    run.receipt["references"] = {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (reference, current)}
    run.receipt["candidate"] = {
        "diagnostic_only": True, "production_changed": False,
        "delta": "Only the three held payload assignments are conditional on the "
                 "newly computed corresponding stall flag, after all previous-edge comparisons.",
        "unchanged": "known(), X/Z, reset, handshake, response scheduling, access, "
                     "scratch and completion assertions; no monitor inlining",
        "decision_rule": "Useful prefix headroom requires both balanced candidate "
                         "runs at least 15% faster than their paired baseline. "
                         "Even that requires complete-fixture follow-up before adoption.",
    }
    fixture = Fixture(CONFIGS["B"], 17, 2)
    integer, expected = fixture.run(Integer())
    floating, _ = fixture.run(Floating())
    absolute = max(abs(a/Q-b) for a, b in zip(integer, floating))
    norm_error = abs(sum((a/Q)**2 for a in integer)**0.5 - 1)
    assert absolute <= 0.002 and norm_error <= 0.002
    run.receipt["fixture"] = {
        "configuration": dataclasses.asdict(fixture.c), "seed": 17, "mode": 2,
        "prefix_cycles": 100000, "mathematical_max_abs_error": absolute,
        "l2_error": norm_error, "full_fixture_complete": False}
    memory = memory_file(run, fixture, "input")
    original = observations(bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4))
    candidate = conditional_capture(original)
    outputs, timings = {}, {}
    retained = None
    if retained_prefix:
        retained_prefix = (ROOT/retained_prefix).resolve()
        assert retained_prefix.is_relative_to(ROOT/"evidence/preparation")
        retained = json.loads((retained_prefix/"receipt.json").read_text())
        assert all(retained["source_sha256"][name] == digest
                   for name, digest in run.receipt["source_sha256"].items()
                   if name != "tests/monitor_cost.py"), "changed prefix inputs"
        assert memory.read_bytes() == (retained_prefix/"input.mem").read_bytes()
        run.receipt["retained_prefix_receipt"] = str(
            (retained_prefix/"receipt.json").relative_to(ROOT))
    for name, source, recorded in (
            ("baseline-recorded", original, True), ("candidate-recorded", candidate, True),
            ("baseline-timing-1", original, False), ("candidate-timing-1", candidate, False),
            ("candidate-timing-2", candidate, False), ("baseline-timing-2", original, False)):
        folder = run.directory / name
        text = monitored_prefix(source, folder, 100000, baseline=not recorded)
        if retained:
            old_tb = retained_prefix/name/"tb.sv"
            assert old_tb.read_text().replace(str(retained_prefix), str(run.directory)) == text
            paths = [old_tb, retained_prefix/(name+"-simulate.stdout"),
                     retained_prefix/(name+"-simulate.stderr")]
            if recorded:
                paths.append(retained_prefix/name/"public-samples.mem")
            run.receipt.setdefault("retained_artifact_sha256", {}).update({
                str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in paths})
            outputs[name] = paths[1].read_text()
            timings[name] = retained["measurements"][name]["simulation_s"]
            run.receipt.setdefault("measurements", {})[name] = retained["measurements"][name]
        else:
            outputs[name], timings[name] = simulate(run, name, text)
        assert outputs[name].count("DIAGNOSTIC_STOP_INCOMPLETE") == 1
        assert "TRANSCRIPT_COMPLETE" not in outputs[name]
        writes_checked(outputs[name], expected)
    baseline = outputs["baseline-recorded"]
    assert records(baseline) == records(outputs["candidate-recorded"]), "recorded transcript delta"
    artifacts = retained_prefix if retained else run.directory
    sampled = changes(artifacts / "baseline-recorded/public-samples.mem")
    assert sampled == changes(artifacts / "candidate-recorded/public-samples.mem")
    samples = int(re.search(r"^SAMPLES (\d+)$", baseline, re.M)[1])
    assert samples == 300004
    # Equal indexed change streams imply equal held values at every intervening sample.
    tags = ("T ", "R ", "W ", "PROGRESS ", "DIAGNOSTIC_STOP_")
    traffic = lambda out: [line for line in out.splitlines() if line.startswith(tags)]
    for out in outputs.values():
        assert traffic(out) == traffic(baseline), "transaction cycle/payload/response delta"
    run.receipt["assertions"].append({
        "sampled_public_and_host_observations_exact": samples,
        "wide_change_records_exact": len(sampled),
        "request_records_exact": sum(s.startswith("T ") for s in baseline.splitlines()),
        "response_records_exact": sum(s.startswith("R ") for s in baseline.splitlines()),
        "independent_prefix_writes": writes_checked(baseline, expected),
        "all_six_arms_identical_public_traffic": True})
    run.save()
    small = Fixture(CONFIGS["A"], 17, 0)
    exact, scratch = small.run(Integer())
    mem = memory_file(run, small, "boundary-input")
    for phase in (None, "request", "output", "done"):
        text = bench(small, mem, (small.layout["end"]-SCRATCH)//4,
                     reset_phase="output" if phase == "done" else phase)
        text = stall_coverage(observations(text))
        if phase:
            old = {"request": "mem_req_valid && !mem_req_ready",
                   "output": "emb_valid && !emb_ready",
                   "done": "emb_valid && !emb_ready"}[phase]
            flag, count = {"request": ("stalled_request", "req_hold"),
                           "output": ("stalled_embedding", "emb_hold"),
                           "done": ("stalled_done", "done_hold")}[phase]
            before = f"  if({old} && !reset_done) begin"
            assert text.count(before) == 1
            text = text.replace(before, f"  if({flag} && {count}>=2 && !reset_done) begin")
            if phase == "done":
                text = text.replace("RESET_OBSERVED output", "RESET_OBSERVED done")
        arms = []
        for name, source in (("baseline", text), ("candidate", conditional_capture(text))):
            out, _ = simulate(run, f"boundary-{phase or 'release'}-{name}", source)
            writes_checked(out, scratch, complete=phase is None or phase == "done")
            coverage = re.search(r"^STALL_COVERAGE (.*)$", out, re.M)
            assert coverage, "missing stall-event observations"
            counts = list(map(int, coverage[1].split()))
            assert len(counts) == 9
            if phase:
                offset = {"request": 0, "output": 3, "done": 6}[phase]
                assert counts[offset] > 0 and counts[offset+1] >= 2
                assert f"RESET_OBSERVED {phase}" in out and "RESET_COMPLETE" in out
            else:
                assert all(n > 0 for n in counts), "stall entry/hold/release not exercised"
                assert out.count("TRANSCRIPT_COMPLETE") == 1
                beats = [int(s.split()[2], 16) for s in out.splitlines() if s.startswith("E ")]
                assert beats == [v & 0xffffffff for v in exact]
            arms.append(out)
        assert records(arms[0]) == records(arms[1]), "boundary public transcript delta"
        run.receipt["coverage"].append({
            "boundary": phase or "all-channel-entry-hold-release",
            "baseline_candidate_exact": True, "stall_counts": counts})
        run.save()
    ratios = [timings[f"candidate-timing-{i}"]/timings[f"baseline-timing-{i}"]
              for i in (1, 2)]
    run.receipt["cost_comparison"] = {
        "baseline_s": [timings[f"baseline-timing-{i}"] for i in (1, 2)],
        "candidate_s": [timings[f"candidate-timing-{i}"] for i in (1, 2)],
        "candidate_over_baseline": ratios,
        "useful_prefix_headroom": all(r <= 0.85 for r in ratios),
        "adopted": False,
        "limitation": "Prefix is deliberately incomplete; no aggregate compliance, "
                      "dominant-cost attribution or RTL defect is established."}
    run.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--repair-of", default=(
        "evidence/preparation/q40-current-monitored-host-b17-007/receipt.json"))
    parser.add_argument("--retained-prefix")
    args = parser.parse_args()
    run = Run(ROOT/args.output, budget=110, repair_of=args.repair_of)
    try:
        run.tools(("python3", "iverilog", "vvp"))
        probe(run, args.retained_prefix)
        run.finish("diagnostic-complete")
    except Exception as error:
        run.receipt["traceback"] = traceback.format_exc()
        run.finish("failed", str(error))
        raise
    print(json.dumps({"receipt": args.output + "/receipt.json",
                      "cost_comparison": run.receipt["cost_comparison"]}))


if __name__ == "__main__":
    main()
