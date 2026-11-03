"""RoPE component checks using exact finite frequency rules and mathematical trig."""

import argparse
import hashlib
import math
import shutil
import sys
from fractions import Fraction
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from numerical_reference import arithmetic, decode, encode, sqrt_encode


@lru_cache(maxsize=None)
def frequency(mode, dimension, index):
    if mode == 1 and index >= dimension // 8:
        return 0
    if index == 0:
        return encode(Fraction(1))
    theta = (10000, 1000000, 100)[mode]
    root = sqrt_encode(Fraction(theta))
    product = encode(Fraction(1))
    bit = dimension // 4
    while bit:
        if index & bit:
            product = arithmetic(0, 1, product, root)[0]
        bit >>= 1
        if bit:
            root = sqrt_encode(decode(root)[2])
    return arithmetic(1, 0, encode(Fraction(1)), product)[0]


def rotation(mode, dimension, index, position, first, second):
    angle = arithmetic(0, 1, frequency(mode, dimension, index),
                       encode(Fraction(position)))[0]
    angle = float(decode(angle)[2])
    sine = encode(Fraction(math.sin(angle)), math.copysign(1, math.sin(angle)) < 0,
                  exponent_bits=8, fraction_bits=7) << 16
    cosine = encode(Fraction(math.cos(angle)), math.copysign(1, math.cos(angle)) < 0,
                    exponent_bits=8, fraction_bits=7) << 16
    ac = arithmetic(0, 1, first << 16, cosine)[0]
    bs = arithmetic(0, 1, second << 16, sine)[0]
    bc = arithmetic(0, 1, second << 16, cosine)[0]
    as_ = arithmetic(0, 1, first << 16, sine)[0]
    low = arithmetic(0, 3, arithmetic(0, 0, ac, bs ^ 0x80000000)[0], 0)[0]
    high = arithmetic(0, 3, arithmetic(0, 0, bc, as_)[0], 0)[0]
    return low | high << 16


def cases():
    for seed in (17, 43, 89):
        for mode, dimension in ((0, 4), (1, 8), (0, 256), (1, 512), (2, 32)):
            indices = sorted({0, 1, dimension // 2 - 1, dimension // 8 - 1,
                              dimension // 8})
            for index in indices:
                if index < 0 or index >= dimension // 2:
                    continue
                for position in (0, 15, 16, 510, 511, 512, 1024, 131071):
                    first = encode(Fraction(((13 * position + 5 * index + seed) & 31) - 16, 32),
                                   exponent_bits=8, fraction_bits=7)
                    second = encode(Fraction(((13 * position + 5 * (index + dimension // 2) +
                                               seed) & 31) - 16, 32),
                                    exponent_bits=8, fraction_bits=7)
                    yield (mode, dimension, index, position, first | second << 16,
                           rotation(mode, dimension, index, position, first, second), 0)
    for mode, dimension, index, position, error in (
            (3, 256, 0, 0, 6), (0, 0, 0, 0, 5), (0, 256, 128, 0, 5),
            (1, 512, 0, 131072, 5)):
        yield mode, dimension, index, position, 0, 0, error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/rotary")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    experiment = Experiment(args.out, "verifier-rotary", source_inputs(), args.repair_of)
    error = None
    try:
        experiment.run("verilator-version", ["verilator", "--version"], 30)
        experiment.run("cxx-version", ["g++", "--version"], 30)
        experiment.run("make-version", ["make", "--version"], 30)
        fixture = experiment.out / "vectors.txt"
        count = 0
        with fixture.open("w") as stream:
            for index, row in enumerate(cases()):
                stream.write(" ".join(map(str, (index, *row))) + "\n")
                count += 1
        experiment.receipt["fixtures"] = {
            "path": str(fixture.relative_to(ROOT)), "count": count,
            "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
            "seeds": [17, 43, 89], "expected_computed_before_observation": True,
            "frequency_reference": "SPEC finite binary32 root/product/reciprocal rules",
            "trig_reference": "binary64 mathematical sine/cosine, then BF16 RNE",
        }
        obj = experiment.relative / "compile-obj"
        experiment.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
            "--top-module", "anvil_en1_rotary_pair", "--Mdir", str(obj),
            "-j", "2", "rtl/anvil_en1_rotary_pair.sv", "rtl/anvil_en1_rope_frequency.sv",
            "rtl/anvil_en1_sincos.sv", "rtl/anvil_en1_uint_to_fp32.sv",
            "rtl/anvil_en1_fp32.sv", "rtl/anvil_en1_fp32_divsqrt.sv",
            str(ROOT / "tests/rotary.cpp"),
        ], 1800)
        output = experiment.run("simulation", [
            str(obj / "Vanvil_en1_rotary_pair"), str(fixture.relative_to(ROOT)),
        ], 2400)
        if f"SUMMARY rotary comparisons={count} " not in output:
            raise RuntimeError("incomplete rotary comparisons")
        experiment.receipt["comparison_count"] = count
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = experiment.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return experiment.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
