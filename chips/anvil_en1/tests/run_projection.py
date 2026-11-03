"""Production-width scalar projections with exact ordered, independent references."""

import argparse
import hashlib
import shutil
import struct
import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from numerical_reference import XorShift32, decode, encode
from text_reference import project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/projection")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    experiment = Experiment(args.out, "verifier-projection", source_inputs(), args.repair_of)
    error = None
    try:
        experiment.run("verilator-version", ["verilator", "--version"], 30)
        experiment.run("cxx-version", ["g++", "--version"], 30)
        experiment.run("make-version", ["make", "--version"], 30)
        cases = []
        fixture_hashes = {}
        images = experiment.out / "checkpoint-images"
        images.mkdir()
        for seed in (17, 43, 89):
            for precision in (0, 1):
                for columns in (8, 31, 32, 33, 1536, 2560, 6144, 10240, 12288):
                    name = f"s{seed}-p{precision}-c{columns}"
                    rng = XorShift32(seed)
                    source_words = [encode(Fraction(((13 * 17 + 5 * c + seed) & 31) - 16, 32),
                                           exponent_bits=8, fraction_bits=7)
                                    for c in range(columns)]
                    source = [decode(word, 8, 7)[2] for word in source_words]
                    stride = ((columns + 1) // 2 * 4 if precision == 0 else
                              (18 * ((columns + 31) // 32) + 3) // 4 * 4)
                    packed = bytearray()
                    selected = []
                    for row in range(2):
                        payload = bytearray()
                        values = []
                        if precision:
                            for block in range((columns + 31) // 32):
                                nibbles = [rng.next() & 15 for _ in range(32)]
                                payload += struct.pack("<e", 1 / 32)
                                payload += bytes(nibbles[j] | nibbles[j + 16] << 4
                                                 for j in range(16))
                                values += [Fraction(n - 8, 32) for n in nibbles]
                        else:
                            for _ in range(columns):
                                value = Fraction((rng.next() & 31) - 16, 64)
                                word = encode(value, exponent_bits=8, fraction_bits=7)
                                payload += struct.pack("<H", word)
                                values.append(decode(word, 8, 7)[2])
                        packed += payload + bytes(stride - len(payload))
                        if row == 1:
                            selected = values[:columns]
                    expected = encode(project([selected], source)[0],
                                      exponent_bits=8, fraction_bits=7)
                    weights_path = images / (name + "-weights.bin")
                    source_path = images / (name + "-source.bin")
                    weights_path.write_bytes(packed)
                    source_path.write_bytes(b"".join(struct.pack("<H", word)
                                                    for word in source_words))
                    for path in (weights_path, source_path):
                        fixture_hashes[str(path.relative_to(experiment.out))] = (
                            hashlib.sha256(path.read_bytes()).hexdigest())
                    cases.append([name, columns, precision, stride, expected,
                                  str(weights_path.relative_to(ROOT)),
                                  str(source_path.relative_to(ROOT))])
            print(f"PROGRESS projection fixtures seed={seed} cases={len(cases)}", flush=True)
        manifest = experiment.out / "cases.txt"
        manifest.write_text("".join(" ".join(map(str, row)) + "\n" for row in cases))
        fixture_hashes[manifest.name] = hashlib.sha256(manifest.read_bytes()).hexdigest()
        experiment.receipt["fixtures"] = fixture_hashes
        experiment.receipt["expected_computed_before_observation"] = True
        experiment.receipt["seeds"] = [17, 43, 89]
        experiment.save()
        obj = experiment.relative / "compile-obj"
        experiment.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
            "--top-module", "anvil_en1_projection", "--Mdir", str(obj),
            "-j", "2", "rtl/anvil_en1_projection.sv", "rtl/anvil_en1_weight_read.sv",
            "rtl/anvil_en1_fp32.sv", str(ROOT / "tests/projection.cpp"),
        ], 1800)
        output = experiment.run("simulation", [
            str(obj / "Vanvil_en1_projection"), str(manifest.relative_to(ROOT)),
        ], 2400)
        components = sum(row[1] for row in cases)
        if (f"SUMMARY projection cases={len(cases)} component_comparisons={components} "
                not in output or
                sum(line.startswith("CASE ") for line in output.splitlines()) != len(cases)):
            raise RuntimeError("incomplete projection comparisons")
        experiment.receipt["projection_comparisons"] = len(cases)
        experiment.receipt["source_component_comparisons"] = components
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = experiment.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return experiment.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
