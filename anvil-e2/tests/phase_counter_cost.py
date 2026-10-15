"""Diagnostic-only exact recurring responder phase counters."""
import argparse
import dataclasses
import json
import re
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from accept_delay_cost import boundaries, cost_record, exact_samples, prepare
from model import CONFIGS, Fixture, Floating, Integer, Q, SCRATCH
from monitor_cost import memory_file, records, simulate, writes_checked
from verify import ROOT, Run, bench


def candidate(text, recorded=False):
    replacements = (
        ("integer requests=0,responses=0,",
         "integer readiness_phase=0,response_phase=0;\n"
         "integer requests=0,responses=0,"),
        ("  cycles=cycles+1;",
         "  cycles=cycles+1;\n"
         "  if(readiness_phase==6) readiness_phase=0;\n"
         "  else readiness_phase=readiness_phase+1;"),
        ("  mem_req_ready=(cycles%7!=0 && cycles%7!=1 && cycles%7!=2);",
         "  mem_req_ready=(readiness_phase>=3);"),
        ("   pending=1; response_at=cycles+2+(requests%3); requests=requests+1;",
         "   pending=1; response_at=cycles+2+response_phase; requests=requests+1;\n"
         "   if(response_phase==2) response_phase=0;\n"
         "   else response_phase=response_phase+1;"),
    )
    original = text
    for before, after in replacements:
        assert text.count(before) == 1, "phase replacement not unique"
        text = text.replace(before, after)
    restored = text
    for before, after in reversed(replacements):
        restored = restored.replace(after, before)
    assert restored == original, "unexpected responder delta"
    if recorded:
        # These independent modulo assertions are absent from timing arms.
        text = text.replace(
            "  mem_req_ready=(readiness_phase>=3);",
            """  if(readiness_phase!==cycles%7) $fatal(1,"READINESS_PHASE");
  mem_req_ready=(readiness_phase>=3);""")
        text = text.replace(
            "   pending=1; response_at=cycles+2+response_phase;",
            """   if(response_phase!==requests%3) $fatal(1,"RESPONSE_PHASE");
   pending=1; response_at=cycles+2+response_phase;""")
        text = text.replace("endmodule", """
final begin
 if(readiness_phase!==cycles%7 || response_phase!==requests%3)
  $fatal(1,"TERMINAL_PHASE");
 $display("PHASE_COVERAGE %0d %0d %0d %0d",
          cycles,requests,readiness_phase,response_phase);
end
endmodule
""")
    return text


def probe(run):
    run.receipt["candidate"] = {
        "diagnostic_only": True, "adopted": False, "production_changed": False,
        "delta": "Replace cycles modulo seven and requests modulo three only "
                 "with exact recurring integer phase counters.",
        "ordering": "Readiness phase advances after cycles increments; response "
                    "delay uses the old request phase before increment. Neither "
                    "counter resets because cycles/requests do not reset.",
        "decision_rule": "Both balanced AB/BA unrecorded elapsed and child-user-CPU "
                         "ratios must be <=0.85 before complete B17/C89 follow-up. "
                         "No prefix result establishes aggregate acceptance."}
    fixture = Fixture(CONFIGS["B"], 17, 2)
    integer, expected = fixture.run(Integer())
    floating, _ = fixture.run(Floating())
    absolute = max(abs(a/Q-b) for a, b in zip(integer, floating))
    norm = abs(sum((a/Q)**2 for a in integer)**.5-1)
    assert absolute <= .002 and norm <= .002
    run.receipt["fixture"] = {
        "configuration": dataclasses.asdict(fixture.c), "seed": 17, "mode": 2,
        "prefix_cycles": 100000, "mathematical_max_abs_error": absolute,
        "l2_error": norm, "complete_fixture": False}
    memory = memory_file(run, fixture, "input")
    original = bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4)
    arms = (("baseline-recorded", False, True), ("candidate-recorded", True, True),
            ("baseline-timing-1", False, False), ("candidate-timing-1", True, False),
            ("candidate-timing-2", True, False), ("baseline-timing-2", False, False))
    outputs = {}
    for name, changed, recorded in arms:
        text = prepare(original, run.directory/name, recorded)
        if changed:
            text = candidate(text, recorded)
        outputs[name], _ = simulate(run, name, text)
        assert outputs[name].count("DIAGNOSTIC_STOP_INCOMPLETE") == 1
        assert "TRANSCRIPT_COMPLETE" not in outputs[name]
        writes_checked(outputs[name], expected)
    baseline = outputs["baseline-recorded"]
    assert records(baseline) == records(outputs["candidate-recorded"])
    nchanges = exact_samples(run, "baseline-recorded", "candidate-recorded")
    nsamples = int(re.search(r"^SAMPLES (\d+)$", baseline, re.M)[1])
    assert nsamples == 300004
    tags = ("T ", "R ", "W ", "PROGRESS ", "DIAGNOSTIC_STOP_")
    traffic = lambda out: [s for s in out.splitlines() if s.startswith(tags)]
    assert all(traffic(out) == traffic(baseline) for out in outputs.values())
    phase = re.search(r"^PHASE_COVERAGE (\d+) (\d+) (\d+) (\d+)$",
                      outputs["candidate-recorded"], re.M)
    assert phase and int(phase[1]) == 100000 and int(phase[2]) > 3
    run.receipt["assertions"].append({
        "sampled_public_host_observations_exact": nsamples,
        "change_records_exact": nchanges,
        "request_records": sum(s.startswith("T ") for s in baseline.splitlines()),
        "response_records": sum(s.startswith("R ") for s in baseline.splitlines()),
        "independent_prefix_writes": writes_checked(baseline, expected),
        "all_six_arms_traffic_exact": True,
        "modulo_phase_invariants": list(map(int, phase.groups())),
        "readiness_wraps": int(phase[1])//7,
        "request_phase_wraps": int(phase[2])//3})
    measured = cost_record(run, [name for name, _, _ in arms])
    ratios = {
        key: [measured[f"candidate-timing-{i}"][key] /
              measured[f"baseline-timing-{i}"][key] for i in (1, 2)]
        for key in ("elapsed_s", "child_user_cpu_s")}
    run.receipt["cost_comparison"] = {
        "arms": measured, "candidate_over_baseline": ratios,
        "useful_prefix_headroom": all(v <= .85 for pair in ratios.values() for v in pair),
        "adopted": False, "limitation": "Incomplete prefix; no aggregate acceptance."}
    run.save()
    boundaries(run, transform=candidate)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    run = Run(ROOT/args.output, budget=110, repair_of=
              "evidence/preparation/q40-response-edge-aggregate-cost-001/receipt.json")
    try:
        run.tools(("python3", "iverilog", "vvp"))
        probe(run)
        run.finish("diagnostic-complete")
    except Exception as error:
        run.receipt["traceback"] = traceback.format_exc()
        run.finish("failed", str(error))
        raise
    print(json.dumps({"receipt": args.output+"/receipt.json",
                      "cost_comparison": run.receipt["cost_comparison"],
                      "boundary_pairs": len(run.receipt["coverage"])}))


if __name__ == "__main__":
    main()
