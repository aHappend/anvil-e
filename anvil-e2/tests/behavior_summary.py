"""Regress the behavior coverage gate using retained results, without HDL reruns."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify import ROOT, Run, assert_behavior_coverage, sources


def validate(path):
    raw = path.read_bytes()
    retained = json.loads(raw)
    assert retained["status"] == "failed"
    assert retained["error"] == "'str' object has no attribute 'get'"
    assertions = retained["assertions"]
    assert any(isinstance(a, str) for a in assertions), "missing original trigger"
    try:
        any(a.get("integer_extremes") for a in assertions)
    except AttributeError as error:
        assert str(error) == retained["error"]
    else:
        raise AssertionError("original coverage-gate failure not reproduced")
    current = sources()
    differences = {p for p, digest in retained["source_sha256"].items()
                   if current.get(p) != digest}
    assert differences == {"tests/verify.py"}, differences
    assert_behavior_coverage(SimpleNamespace(receipt=retained))
    rejected = []
    for missing in ("integer_extremes", "axial_swap", "vision_head_0", "vision_head_1",
                    "text_head_0", "text_head_1", "text_head_2", "text_head_3"):
        altered = [a for a in assertions if not (
            isinstance(a, dict) and (
                (missing == "integer_extremes" and a.get(missing)) or
                a.get("operator") == missing))]
        try:
            assert_behavior_coverage(SimpleNamespace(receipt={"assertions": altered}))
        except AssertionError:
            rejected.append(missing)
        else:
            raise AssertionError(f"missing coverage accepted: {missing}")
    executions = retained["executions"]
    assert executions and all(not e.get("timed_out", False) for e in executions)
    assert all(e.get("exit_code") == 0 or (
        Path(e["stdout"]).name.startswith("illegal-") and e.get("exit_code") != 0)
               for e in executions), "unexpected tool failure"
    fixtures = [c for c in retained["coverage"] if "compared_components" in c
                and c.get("expected_error") == 0]
    mandatory = {
        f"{label}-s{seed}-m{mode}-d{dimension}"
        for label, seeds, dimensions in (
            ("A", (17,), (1, 2, 4, 6)),
            ("B", (17, 89), (12,)),
            ("C", (17, 89), (12,)),
            ("D", (17,), (768, 512, 256, 128)))
        for seed in seeds for mode in (0, 1, 2) for dimension in dimensions
    }
    expected = mandatory | {"zero-pooled-vector", "back-to-back",
                            "six-layer-numerical-regression"}
    assert {f["case"] for f in fixtures} == expected
    assert len(fixtures) == len(expected), "duplicate fixture records"
    for fixture in fixtures:
        assert fixture["mathematical_max_abs_error"] <= 0.002
        assert fixture["l2_error"] <= 0.002
        assert fixture["compared_components"] > 0
        transcript = ROOT/fixture["transcript"]
        assert transcript.read_text().count("TRANSCRIPT_COMPLETE") == 1
    print(json.dumps({
        "retained_receipt": str(path.relative_to(ROOT)),
        "retained_sha256": hashlib.sha256(raw).hexdigest(),
        "original_exception_reproduced": True,
        "repaired_gate_passed": True,
        "missing_coverage_rejected": rejected,
        "unchanged_existing_sources_except": sorted(differences),
        "retained_completed_fixture_records": len(fixtures),
        "retained_mandatory_fixture_records": len(mandatory),
        "retained_coverage_records": len(retained["coverage"]),
        "hdl_rerun": False,
        "acceptance_claim": False,
    }, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--retained", required=True)
    parser.add_argument("--output")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    path = (ROOT/args.retained).resolve()
    assert path.is_relative_to(ROOT/"evidence/verification/behavior")
    if args.output is None:
        validate(path)
        return
    directory = (ROOT/args.output).resolve()
    assert directory.is_relative_to(ROOT/"evidence/preparation")
    run = Run(directory, budget=30, repair_of=args.repair_of or args.retained)
    run.receipt["original_behavior_failure"] = args.retained
    try:
        run.tools(("python3",))
        out, _, _ = run.command(
            [sys.executable, Path(__file__).resolve(), "--retained", args.retained],
            "coverage-gate-regression", timeout=20)
        run.receipt["assertions"].append(json.loads(out))
    except Exception as error:
        run.finish("failed", str(error))
        raise
    run.finish("passed")


if __name__ == "__main__":
    main()
