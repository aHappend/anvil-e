"""Bounded reference-generation/reuse diagnostic; not hardware acceptance."""

import argparse
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from text_cases import prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/text-reference-reuse")
    parser.add_argument("--repair-of", required=True)
    parser.add_argument("--historical-baseline", required=True)
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-independent-reference-reuse",
                     source_inputs(), args.repair_of)
    error = None
    try:
        exp.run("python-version", [sys.executable, "--version"], 30)
        started = time.monotonic()
        manifest = prepare(exp, (1, 2), (0, 1), (17, 43, 89), (1, 16, 17))
        exp.receipt["preparation_seconds"] = time.monotonic() - started
        exp.save()
        output = exp.run("exact-comparison", [
            sys.executable, "-B", "tests/check_text_cases.py",
            "--fixture-set", str(manifest.relative_to(ROOT)),
            "--historical-baseline", args.historical_baseline], 2400)
        exp.receipt["comparison_summary"] = output.strip()
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
