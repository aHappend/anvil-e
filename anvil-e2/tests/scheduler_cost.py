"""Paired public-pin scheduler diagnostic; not an acceptance check."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Fixture, Integer
from verify import ROOT, Run, fixture_candidates


def transcript_records(data):
    return [line for line in data.splitlines()
            if line.startswith((b"W ", b"E ", b"C ")) or line == b"TRANSCRIPT_COMPLETE"]


def analyze(run, reference):
    """Analyze retained failures without resuming or rescoring killed tools."""
    reference = (ROOT/reference).resolve()
    assert reference.is_relative_to(ROOT/"evidence/preparation")
    original_path = reference/"receipt.json"
    original = json.loads(original_path.read_text())
    run.receipt["retained_artifacts"] = {}

    def retain(path):
        run.receipt["retained_artifacts"][str(path.relative_to(ROOT))] = (
            hashlib.sha256(path.read_bytes()).hexdigest())

    retain(original_path)
    for name, digest in original["source_sha256"].items():
        if name.startswith("rtl/") or name == "tests/model.py":
            assert run.receipt["source_sha256"][name] == digest, "analysis input changed"
    serial, parallel = original["scheduler_batches"]
    assert serial["workers"] == 1 and parallel["workers"] == 2
    comparisons = []
    for label, seed in (("B", 17), ("C", 89)):
        fixture = Fixture(CONFIGS[label], seed, 2)
        expected, writes = fixture.run(Integer())
        records = []
        for arm in ("serial", "two-worker"):
            name = f"{arm}-{label}-s{seed}-m2-d12"
            child_path = reference/name/"receipt.json"
            child = json.loads(child_path.read_text())
            retain(child_path)
            path = reference/name/(name+"-simulate.stdout")
            retain(path)
            data = path.read_bytes()
            # Killed simulators may leave a partial final line. Preserve it;
            # compare only complete records and explicitly fail completeness.
            lines = data.splitlines(keepends=True)
            incomplete_tail = bool(lines and not lines[-1].endswith(b"\n"))
            observed = {}
            beats = []
            complete = False
            for line in lines:
                if not line.endswith(b"\n"):
                    continue
                fields = line.split()
                if fields and fields[0] == b"W":
                    assert len(fields) == 3
                    address, value = (int(v, 16) for v in fields[1:])
                    observed.setdefault(address, []).append(value)
                elif fields and fields[0] == b"E":
                    value = int(fields[2], 16)
                    beats.append(value-(1 << 32) if value & (1 << 31) else value)
                elif line.strip() == b"TRANSCRIPT_COMPLETE":
                    complete = True
            for address, values in observed.items():
                assert address in writes and values == writes[address][:len(values)]
            assert beats == expected[:len(beats)]
            if arm == "serial":
                assert child["status"] == "passed" and complete
                assert beats == expected and observed == writes
            else:
                assert child["status"] == "failed" and not complete
                assert child["executions"][-1]["timed_out"]
            records.append({
                "arm": arm, "status": child["status"], "complete": complete,
                "partial_final_line": incomplete_tail,
                "compared_writes": sum(map(len, observed.values())),
                "compared_addresses": len(observed), "compared_components": len(beats),
                "full_independent_comparison": arm == "serial",
                "prefix_only_not_acceptance": arm != "serial",
            })
        comparisons.append({"configuration": label, "seed": seed, "mode": 2,
                            "arms": records})
    run.receipt["paired_comparison"] = {
        "reference_status": original["status"],
        "serial_elapsed_s": serial["elapsed_s"],
        "two_worker_elapsed_s_before_failure": parallel["elapsed_s"],
        "extra_elapsed_s_without_completion": parallel["elapsed_s"]-serial["elapsed_s"],
        "useful_headroom": False, "adopted": False,
        "capacity_at_execution_start": original["diagnostic_scope"]["capacity_before"],
        "analysis_time_capacity_not_execution_end": capacity(),
        "independent_comparisons": comparisons,
        "remaining_cost_surface": (
            "Real-DUT vision dense projection/helper and repeated attention K/V "
            "transaction scheduling; request gaps include bus and arithmetic work "
            "and do not isolate simulator CPU cost."),
    }


def capacity():
    result = {"logical_cpus": os.cpu_count(),
              "affinity_cpus": sorted(os.sched_getaffinity(0)),
              "load_average": os.getloadavg()}
    # Linux entitlement is distinct from the much larger affinity mask.
    for name in ("cpu.max", "cpu.stat", "cpuset.cpus.effective"):
        path = Path("/sys/fs/cgroup")/name
        result[name] = path.read_text().strip() if path.is_file() else None
    quota = result["cpu.max"]
    result["quota_cpus"] = (None if not quota or quota.split()[0] == "max"
                            else int(quota.split()[0])/int(quota.split()[1]))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--analyze", help="read-only analysis of an existing paired directory")
    args = parser.parse_args()
    directory = (ROOT/args.output).resolve()
    assert directory.is_relative_to(ROOT/"evidence/preparation")
    run = Run(directory)
    if args.analyze:
        try:
            run.tools(("python3",))
            analyze(run, args.analyze)
        except Exception as error:
            (directory/"analysis.stderr").write_text(traceback.format_exc())
            run.finish("failed", str(error))
            raise
        summary = json.dumps(run.receipt["paired_comparison"], indent=2)
        (directory/"analysis.stdout").write_text(summary+"\n")
        (directory/"analysis.stderr").write_text("")
        run.receipt["analysis_logs"] = {
            "stdout": str((directory/"analysis.stdout").relative_to(ROOT)),
            "stderr": str((directory/"analysis.stderr").relative_to(ROOT)),
        }
        run.finish("diagnostic-analysis")
        print(summary)
        return 0
    run.receipt["diagnostic_scope"] = {
        "acceptance_evidence": False,
        "cases": [["B", 17, 2], ["C", 89, 2]],
        "runner_timeout_s": 110, "admitted_timeout_s": 120,
        "useful_benefit_rule": "serial/parallel > 1.10 and saved seconds > 1",
        "common_deadline_for_both_arms": run.deadline,
        "capacity_before": capacity(),
    }
    run.save()
    try:
        run.tools(("python3", "iverilog", "vvp"))
        arms = []
        for arm, workers in (("serial", 1), ("two-worker", 2)):
            cases = [(f"{arm}-{label}-s{seed}-m2-d12",
                      Fixture(CONFIGS[label], seed, 2))
                     for label, seed in (("B", 17), ("C", 89))]
            arms.append(fixture_candidates(run, cases, workers))
        comparisons = []
        for label, seed in (("B", 17), ("C", 89)):
            contents = []
            for arm in ("serial", "two-worker"):
                name = f"{arm}-{label}-s{seed}-m2-d12"
                contents.append((directory/name/(name+"-simulate.stdout")).read_bytes())
            assert transcript_records(contents[0]) == transcript_records(contents[1]), (
                f"paired transcript differs: {label}")
            comparisons.append({
                "configuration": label, "seed": seed, "mode": 2,
                "identical_complete_transaction_records": True,
                "sha256": hashlib.sha256(
                    b"\n".join(transcript_records(contents[0]))).hexdigest(),
            })
        serial, parallel = (a["elapsed_s"] for a in arms)
        run.receipt["paired_comparison"] = {
            "serial_elapsed_s": serial, "two_worker_elapsed_s": parallel,
            "speedup": serial/parallel, "saved_seconds": serial-parallel,
            "useful_headroom": serial/parallel > 1.10 and serial-parallel > 1,
            "complete_transcript_comparisons": comparisons,
            "capacity_after": capacity(),
        }
        assert len(run.receipt["coverage"]) == 4
        assert time.monotonic() < run.deadline, "paired diagnostic deadline"
    except Exception as error:
        run.receipt["capacity_after_failure"] = capacity()
        run.finish("failed", str(error))
        traceback.print_exc()
        return 1
    run.finish("passed")
    print(json.dumps(run.receipt["paired_comparison"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
