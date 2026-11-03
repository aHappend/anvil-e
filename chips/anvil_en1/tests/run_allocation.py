"""Exact independent footprint inequalities and public strict-limit guard checks."""

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def baseline(model, tokens):
    padded = (tokens + 15) // 16 * 16
    local_layers, kv_heads = (28, 1) if model == 1 else (35, 2)
    return 4 * kv_heads * (
        local_layers * 256 * min(padded, 512) + 7 * 512 * padded)


def bounds():
    results = []
    for model, hidden, kv_heads, text_bytes in (
            (1, 1536, 1, 32768), (2, 2560, 2, 65536)):
        maximum = (0, 1)
        first_fallback = None
        for tokens in range(1, 131073):
            padded = (tokens + 15) // 16 * 16
            matched = baseline(model, tokens)
            for capacity in (1, 3, 64):
                if 2 * hidden * padded <= 3 * 1024 * 1024:
                    bound = (2 * hidden * padded + 4 * kv_heads * 256 * min(padded, 512)
                             + text_bytes + 4 * capacity
                             + min(1024 * 1024, matched // 8))
                else:
                    if first_fallback is None:
                        first_fallback = tokens
                    bound = 1024 * 1024
                if 20 * bound >= 9 * matched:
                    raise AssertionError(f"strict footprint bound violated m={model} "
                                         f"N={tokens} C={capacity} P={bound} B={matched}")
                if bound * maximum[1] > maximum[0] * matched:
                    maximum = bound, matched
        results.append({"model": model, "positions_checked": 131072,
                        "capacities": [1, 3, 64], "maximum_ratio": maximum[0] / maximum[1],
                        "first_fallback_tokens": first_fallback,
                        "first_fallback_baseline_bytes": baseline(model, first_fallback)})
    if [r["first_fallback_tokens"] for r in results] != [1025, 609]:
        raise AssertionError("incorrect production frontier transition")
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/allocation")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-allocation-guard", source_inputs(), args.repair_of)
    error = None
    try:
        exp.receipt["analytic_bounds_only"] = bounds()
        exp.receipt["scope"] = (
            "Public guard behavior and mathematical bounds; not integrated liveness, "
            "handshake baseline traffic, forced-short fallback or physical RAM fit.")
        cases = []

        def case(name, model=1, fallback=0, overlap=0, partition=0,
                 live=100, scratch=0, shadow=100, scratch_shadow=0,
                 text=0, text_shadow=0, working=0, working_shadow=0,
                 matched=1000, clear=0):
            expected = int(
                matched == 0 or overlap or partition or model not in (1, 2) or
                shadow < live or scratch_shadow < scratch or text_shadow < text or
                working_shadow < working or
                20 * live >= 9 * matched or 20 * shadow >= 9 * matched or
                (fallback and (live > 1048576 or shadow > 1048576 or
                               working > 65536 or working_shadow > 65536)) or
                (not fallback and (
                    scratch > min(1048576, matched // 8) or
                    scratch_shadow > min(1048576, matched // 8) or
                    text > (32768 if model == 1 else 65536) or
                    text_shadow > (32768 if model == 1 else 65536))))
            cases.append([name, model, fallback, overlap, partition, live, scratch, shadow,
                          scratch_shadow, text, text_shadow, working, working_shadow,
                          matched, clear, 0 if clear else expected])

        for model in (1, 2):
            for tokens in (1, 16, 17, 511, 512, 513, 609, 1025, 131072):
                matched = baseline(model, tokens)
                edge = (9 * matched - 1) // 20
                for delta in (-1, 0, 1, 2):
                    case(f"ratio-m{model}-n{tokens}-d{delta}", model=model,
                         live=edge + delta, shadow=edge + delta, matched=matched)
        for field in ("scratch", "text", "working", "live"):
            for model in (1, 2):
                limit = {"scratch": 1048576, "text": 32768 if model == 1 else 65536,
                         "working": 65536, "live": 1048576}[field]
                for delta in (-1, 0, 1):
                    settings = {field: limit + delta,
                                {"scratch": "scratch_shadow", "text": "text_shadow",
                                 "working": "working_shadow", "live": "shadow"}[field]: limit + delta}
                    case(f"{field}-m{model}-d{delta}", model=model,
                         fallback=int(field in ("working", "live")), matched=1 << 26,
                         **settings)
        for name, changes in (
                ("overlap", {"overlap": 1}), ("partition", {"partition": 1}),
                ("model-zero", {"model": 0}), ("model-three", {"model": 3}),
                ("zero-baseline", {"matched": 0}),
                ("missing-shadow", {"shadow": 99}),
                ("native-shadow-underflow", {"scratch": 1}),
                ("text-shadow-underflow", {"text": 1}),
                ("working-shadow-underflow", {"working": 1}),
                ("clear-wins", {"overlap": 1, "clear": 1}),
                ("no-scaled-overflow", {"live": (1 << 64) - 1,
                                        "shadow": (1 << 64) - 1, "matched": (1 << 64) - 1})):
            case(name, **changes)
        path = exp.out / "cases.txt"
        path.write_text("".join(" ".join(map(str, row)) + "\n" for row in cases))
        exp.receipt["fixtures"] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()}
        exp.receipt["expected_computed_before_observation"] = True
        exp.save()
        exp.run("verilator-version", ["verilator", "--version"], 30)
        exp.run("cxx-version", ["g++", "--version"], 30)
        exp.run("make-version", ["make", "--version"], 30)
        obj = exp.relative / "compile-obj"
        exp.run("compile", ["verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                           "--top-module", "anvil_en1_allocation_guard", "--Mdir", str(obj),
                           "-j", "2", "rtl/anvil_en1_allocation_guard.sv",
                           str(ROOT / "tests/allocation_guard.cpp")], 1800)
        output = exp.run("simulation", [str(obj / "Vanvil_en1_allocation_guard"),
                                      str(path.relative_to(ROOT))], 2400)
        if f"SUMMARY allocation_guard cases={len(cases)}" not in output:
            raise RuntimeError("incomplete allocation guard comparisons")
        exp.receipt["comparison_cases"] = len(cases)
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError, AssertionError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
