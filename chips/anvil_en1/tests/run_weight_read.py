"""Independent BF16/Q4 decoding, row boundaries, addresses and response errors."""

import argparse
import hashlib
import shutil
import struct
import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from numerical_reference import XorShift32, arithmetic, encode


def vectors(compact=False):
    shapes = (1, 3, 31, 32, 33) if compact else (
        1, 3, 31, 32, 33, 256, 512, 1536, 2560, 6144, 10240, 12288)
    for seed in (17,) if compact else (17, 43, 89):
        rng = XorShift32(seed)
        for precision in (0, 1):
            for columns in shapes:
                stride = ((columns + 1) // 2 * 4 if precision == 0 else
                          (18 * ((columns + 31) // 32) + 3) // 4 * 4)
                image = bytearray()
                values = []
                for row in range(3):
                    payload = bytearray()
                    row_values = []
                    if precision:
                        for block in range((columns + 31) // 32):
                            nibbles = [rng.next() & 15 for _ in range(32)]
                            payload += struct.pack("<e", 1 / 32)
                            payload += bytes(nibbles[j] | nibbles[j + 16] << 4
                                             for j in range(16))
                            row_values += [encode(Fraction(n - 8, 32)) for n in nibbles]
                    else:
                        for _ in range(columns):
                            bf16 = encode(Fraction((rng.next() & 31) - 16, 64),
                                          exponent_bits=8, fraction_bits=7)
                            payload += struct.pack("<H", bf16)
                            row_values.append(arithmetic(0, 2, bf16, 0)[0])
                    image += payload + bytes(stride - len(payload))
                    values.append(row_values)
                for row in (0, 1, 2):
                    for column in sorted({c for c in (0, 1, 15, 16, 31, 32, columns - 1)
                                          if c < columns}):
                        base = 0x100000004
                        row_offset = row * stride
                        offsets = ([row_offset + (column // 2) * 4] if not precision else [
                            (row_offset + (column // 32) * 18) & ~3,
                            (row_offset + (column // 32) * 18 + 2 + column % 16) & ~3])
                        commands = [(base + offset, int.from_bytes(image[offset:offset+4],
                                                                  "little"), 0)
                                    for offset in offsets]
                        yield (precision, base, len(image), 3, columns, stride, row, column,
                               values[row][column], 0, commands)
    for bf16 in (0, 0x8000, 1, 0x8001, 0x7F80, 0xFF80, 0x7FC1, 0x7F81, 0x7F7F):
        expected, error = arithmetic(0, 2, bf16, 0)
        yield (0, 0x1000, 4, 1, 1, 4, 0, 0, expected, error,
               [(0x1000, bf16 | 0xDEAD0000, 0)])
    legal = [0, 0x1000, 8, 1, 3, 8, 0, 0, 0, 0, []]
    for field, value, error in ((0, 2, 6), (1, 0x1001, 5), (2, 12, 5),
                                (3, 0, 5), (4, 0, 5), (5, 12, 5),
                                (6, 1, 5), (7, 3, 5), (1, 0xFFFFFFFFFFFFFFFC, 5)):
        invalid = list(legal)
        invalid[field] = value
        invalid[9] = error
        yield tuple(invalid)
    yield (0, 0x1000, 4, 1, 1, 4, 0, 0, 0, 2, [(0x1000, 0x3F80, 1)])
    yield (1, 0x1000, 20, 1, 32, 20, 0, 16, 0, 2,
           [(0x1000, 0xFF002800, 0), (0x1000, 0xFF002800, 1)])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/weight-read")
    parser.add_argument("--compact", action="store_true")
    parser.add_argument("--defect", action="store_true")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    experiment = Experiment(args.out, "verifier-weight-read", source_inputs(), args.repair_of)
    error = None
    try:
        experiment.run("verilator-version", ["verilator", "--version"], 30)
        experiment.run("cxx-version", ["g++", "--version"], 30)
        experiment.run("make-version", ["make", "--version"], 30)
        fixture = experiment.out / "vectors.txt"
        count = 0
        with fixture.open("w") as stream:
            for index, row in enumerate(vectors(args.compact)):
                precision, base, size, rows, columns, stride, r, c, data, err, commands = row
                stream.write(f"{index} {precision} {base:x} {size:x} {rows} {columns} "
                             f"{stride} {r} {c} {data:08x} {err} {len(commands)}\n")
                for address, word, memory_error in commands:
                    stream.write(f"{address:x} {word:08x} {memory_error}\n")
                count += 1
        experiment.receipt["fixtures"] = {
            "path": str(fixture.relative_to(ROOT)), "count": count,
            "sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
            "expected_computed_before_observation": True,
            "seeds": [17] if args.compact else [17, 43, 89],
            "reference": "independent row packing and exact rational conversion",
        }
        variants = [("original", "rtl/anvil_en1_weight_read.sv")]
        if args.defect:
            original = (ROOT / variants[0][1]).read_text()
            needle = "column_hold[4] ? nibble_byte[7:4] : nibble_byte[3:0]"
            if original.count(needle) != 1:
                raise RuntimeError("Q4 nibble mutation site not unique")
            mutant = experiment.out / "q4_nibble_order.sv"
            mutant.write_text(original.replace(
                needle, "column_hold[4] ? nibble_byte[3:0] : nibble_byte[7:4]"))
            variants.append(("q4-nibble-order", str(mutant.relative_to(ROOT))))
            experiment.receipt["mutation"] = {
                "path": str(mutant.relative_to(ROOT)),
                "sha256": hashlib.sha256(mutant.read_bytes()).hexdigest(),
                "intended_assertion": "WEIGHT_VALUE",
            }
        for name, source in variants:
            obj = experiment.relative / (name + "-compile-obj")
            experiment.run(name + "-compile", [
                "verilator", "--binary", "--timing", "-Wno-fatal",
                "--top-module", "weight_read_tb", "--Mdir", str(obj),
                "-j", "2", "tests/weight_read_tb.sv", source, "rtl/anvil_en1_fp32.sv",
            ], 1800)
            output = experiment.run(name + "-simulation", [
                str(obj / "Vweight_read_tb"), "+vectors=" + str(fixture.relative_to(ROOT)),
                "+max_cycles=10000000",
            ], 2400, (0,) if name == "original" else (1, -6))
            if name == "original":
                if f"SUMMARY weight_read comparisons={count} " not in output:
                    raise RuntimeError("incomplete weight-read comparisons")
            elif "WEIGHT_VALUE" not in output:
                raise RuntimeError("Q4 mutant missed its intended value assertion")
            shutil.rmtree(ROOT / obj)
        experiment.receipt["comparison_count"] = count
        experiment.receipt["mutant_rejected"] = args.defect
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        for name in ("original", "q4-nibble-order"):
            obj = experiment.out / (name + "-compile-obj")
            if obj.exists():
                shutil.rmtree(obj)
    return experiment.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
