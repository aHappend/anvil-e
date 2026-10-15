"""Focused synthesis watchdog regression; preparation is not acceptance."""
import argparse
import json
from pathlib import Path
import sys
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify import ROOT, Run, synthesis


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--repair-of", required=True)
    args = parser.parse_args()
    directory = (ROOT / args.output).resolve()
    assert directory.is_relative_to(ROOT / "evidence/preparation")
    original_path = (ROOT / args.repair_of).resolve()
    assert original_path.is_relative_to(ROOT / "evidence")
    original = json.loads(original_path.read_text())
    run = Run(directory, budget=180, repair_of=args.repair_of)
    try:
        failed = [e for e in original["executions"]
                  if Path(e["stdout"]).name == "C-yosys.stdout"]
        assert len(failed) == 1
        failed = failed[0]
        assert original["status"] == "failed"
        assert original["error"] == "tool timeout: C-yosys"
        assert failed["timed_out"] and failed["requested_timeout_s"] == 60
        assert failed["exit_code"] != 0 and failed["cleanup"]["direct_child_reaped"]
        assert failed["remaining_common_s"] > 86000
        assert any(c["config"] == "A" and c["latches"] == 0
                   and c["sequential_cells"] > 0 for c in original["coverage"])
        changed = sorted(p for p, digest in original["source_sha256"].items()
                         if run.receipt["source_sha256"].get(p) != digest)
        assert changed == ["tests/verify.py"], changed
        run.receipt["assertions"].append({
            "diagnosis": "C child watchdog expired before common deadline",
            "original_child_timeout_s": 60,
            "original_remaining_common_s": failed["remaining_common_s"],
            "changed_existing_sources": changed,
        })

        run.save()
        synthesis(run, ("C",))
        coverage = run.receipt["coverage"]
        assert len(coverage) == 1 and coverage[0]["config"] == "C"
        executed = [e for e in run.receipt["executions"]
                    if Path(e["stdout"]).name == "C-yosys.stdout"]
        assert len(executed) == 1
        assert executed[0]["requested_timeout_s"] == 86400
        assert 0 < executed[0]["effective_timeout_s"] <= 180
        assert not executed[0]["timed_out"] and executed[0]["exit_code"] == 0
        run.finish("passed")
    except Exception as error:
        run.finish("failed", str(error))
        traceback.print_exc()
        return 1
    print(f"Focused C synthesis passed: {args.output}/receipt.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
