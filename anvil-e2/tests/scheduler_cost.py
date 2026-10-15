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
from model import CONFIGS, Fixture
from verify import ROOT, Run, fixture_candidates


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
    args = parser.parse_args()
    directory = (ROOT/args.output).resolve()
    assert directory.is_relative_to(ROOT/"evidence/preparation")
    run = Run(directory)
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
            assert contents[0] == contents[1], f"paired transcript differs: {label}"
            comparisons.append({
                "configuration": label, "seed": seed, "mode": 2,
                "identical_complete_transcripts": True,
                "sha256": hashlib.sha256(contents[0]).hexdigest(),
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
        run.finish("failed", str(error))
        traceback.print_exc()
        return 1
    run.finish("passed")
    print(json.dumps(run.receipt["paired_comparison"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
