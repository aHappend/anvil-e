"""Advisory aggregate-cost diagnostic, not an admitted acceptance check.

Execute only the eight mandatory B/C image-mode fixtures under the existing
runner's 110-second deadline. No fixture, oracle, stimulus or tolerance changes.
Failure here preserves a reproducible aggregate-cost observation; it does not
identify an RTL arithmetic defect or certify the unexecuted full suite.
"""
import argparse
import json
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Fixture
from verify import ROOT, Run, execute_fixture


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    directory = (ROOT / args.output).resolve()
    assert directory.is_relative_to(ROOT / "evidence/preparation")
    run = Run(directory)
    cases = [(label, seed, mode) for label in ("B", "C")
             for seed in (17, 89) for mode in (1, 2)]
    run.receipt["diagnostic_scope"] = {
        "acceptance_evidence": False,
        "purpose": "aggregate execution cost of unchanged mandatory subset",
        "planned_cases": [
            {"configuration": label, "seed": seed, "mode": mode}
            for label, seed, mode in cases],
        "excluded": "A/D, B/C text-only and all focused/directed checks",
        "runtime_check_timeout_s": 120,
        "runner_timeout_s": 110,
    }
    run.save()
    try:
        run.tools(("python3", "iverilog", "vvp"))
        for label, seed, mode in cases:
            execute_fixture(run, f"{label}-s{seed}-m{mode}-d12",
                            Fixture(CONFIGS[label], seed, mode))
        assert len(run.receipt["coverage"]) == len(cases)
    except Exception as error:
        run.finish("failed", str(error))
        traceback.print_exc()
        code = 1
    else:
        run.finish("passed")
        code = 0
    print(json.dumps({
        "diagnostic_only": True, "status": run.receipt["status"],
        "completed_cases": len(run.receipt["coverage"]),
        "planned_cases": len(cases),
        "receipt": str((directory / "receipt.json").relative_to(ROOT)),
    }))
    return code


if __name__ == "__main__":
    sys.exit(main())
