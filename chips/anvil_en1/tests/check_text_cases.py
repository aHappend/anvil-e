"""Compare shared independent prefixes with separate evaluations and retained fixtures."""

import argparse
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import ROOT
from run_baseline import schedule
from text_cases import load
from text_fixture import make_text_image
from text_reference import logits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-set", required=True)
    parser.add_argument("--historical-baseline", required=True)
    args = parser.parse_args()
    historical = ROOT / args.historical_baseline
    comparisons = 0
    cases = load(args.fixture_set, (1, 2), (0, 1), (17, 43, 89), (1, 16, 17))
    for case in cases:
        rows = list(schedule(case["model"], case["tokens"], case["reference"]))
        expected = (historical / (case["name"] + "-commands.txt")).read_text()
        observed = "".join(" ".join(map(str, row)) + "\n" for row in rows)
        if observed != expected:
            raise RuntimeError("retained exact K/V baseline differs: " + case["name"])
        comparisons += len(rows)
        if case["seed"] == 17 and case["tokens"] in (1, 16):
            _, tensors = make_text_image(case["model"], case["precision"], case["seed"])
            separate = logits(tensors, case["model"], case["seed"], case["tokens"])
            # JSON normalizes integer dictionary keys exactly as stored in fixtures.
            if json.loads(json.dumps(separate)) != case["reference"]:
                raise RuntimeError("separate prefix evaluation differs: " + case["name"])
    print(json.dumps({"cases": len(cases), "exact_baseline_word_comparisons": comparisons,
                      "separate_full_reference_comparisons": 8, "mismatches": 0}))


if __name__ == "__main__":
    main()
