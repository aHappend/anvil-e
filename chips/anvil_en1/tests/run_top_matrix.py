"""Fresh independent reference/baseline reuse and six reusable compiled top models."""

import argparse
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from coverage_matrix import CAPACITIES, fixture_keys, top_cells
from experiment import Experiment, ROOT, source_inputs
from text_cases import prepare_cases
from verify import Step, execute_step, require_cases


def traffic_observations(candidate, baseline):
    denominators = {}
    for record in baseline:
        if record.get("kind") != "matched-unshared-public-traffic":
            continue
        key = tuple(record[field] for field in ("model", "precision", "seed", "tokens"))
        if (key in denominators or record.get("completed") is not True or
                record.get("mismatches") != 0 or record.get("comparisons", 0) <= 0 or
                record["accepted_external_kv_bytes"] <= 0):
            raise RuntimeError("baseline denominator is duplicated, incomplete or empty")
        denominators[key] = record["accepted_external_kv_bytes"]
    result = []
    for record in candidate:
        if record.get("kind") != "top-numerical":
            continue
        key = tuple(record[field] for field in ("model", "precision", "seed", "tokens"))
        denominator = denominators[key]
        counts = record["public_counts"]
        if (record.get("completed") is not True or record.get("mismatches") != 0 or
                record.get("comparisons") != 32 or counts["reads"] <= 0 or
                counts["reads"] * 4 != counts["weight_bytes"] + counts["input_bytes"] or
                counts["kv_bytes"] < 0 or 100 * counts["kv_bytes"] >= 45 * denominator):
            raise RuntimeError("candidate traffic/numerical comparison failed")
        result.append({
            **{field: record[field] for field in
               ("model", "precision", "seed", "capacity", "tokens", "fallback")},
            "kind": "candidate-public-kv-traffic",
            "accepted_external_kv_bytes": counts["kv_bytes"],
            "matched_unshared_external_kv_bytes": denominator,
            "weight_bytes": counts["weight_bytes"], "original_input_bytes": counts["input_bytes"],
            "total_external_bytes": 4 * counts["reads"],
            "comparisons": counts["reads"], "completed": True, "mismatches": 0,
        })
    if not result:
        raise RuntimeError("candidate has no completed public traffic observations")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/top-matrix")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-representative-top-matrix",
                     source_inputs(), args.repair_of)
    error = None
    began = time.monotonic()
    try:
        exp.run("python-version", [sys.executable, "--version"], 30)
        exp.receipt.update(children=[], observations=[],
                           selection=[cell.__dict__ for cell in top_cells()])
        manifest = prepare_cases(exp, fixture_keys())
        manifest_arg = str(manifest.relative_to(ROOT))
        baseline = execute_step(exp, Step("baseline", "run_baseline.py", (
            "--fixture-set", manifest_arg, "--selection", "representative")))
        if baseline["independent_fixture_manifest"] != exp.receipt["independent_fixture_manifest"]:
            raise RuntimeError("baseline fixture manifest differs")
        candidate = []
        for fallback in (0, 1):
            for capacity in CAPACITIES:
                child = execute_step(exp, Step(f"c{capacity}-f{fallback}", "run_top_batch.py", (
                    "--fixture-set", manifest_arg, "--selection", "representative",
                    "--capacity", str(capacity), "--profile-cycles", "200000", "--pgo",
                    "--build-jobs", "4", *(("--fallback",) if fallback else ()))))
                if child["independent_fixture_manifest"] != exp.receipt["independent_fixture_manifest"]:
                    raise RuntimeError("candidate fixture manifest differs")
                candidate.extend(child["observations"])
                exp.receipt["observations"] = candidate.copy()
                exp.save()
        require_cases([{"observations": candidate}], [cell.key for cell in top_cells()],
                      ("model", "precision", "seed", "capacity", "tokens", "fallback"),
                      "top-numerical")
        exp.receipt["observations"].extend(traffic_observations(
            candidate, baseline["observations"]))
        exp.receipt["scope"] = (
            "20 representative cells, not a Cartesian matrix: complete production layer maps, "
            "both precisions, all three seeds/capacities and ordinary 1/16/17-token plus "
            "forced-fallback 1/17-token jobs. Numerical and classified external-handshake "
            "observations only; integrated allocations, decode, native modalities, history "
            "and production cache have separate producers/coverage obligations.")
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    exp.receipt["complete_elapsed_seconds"] = time.monotonic() - began
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
