"""Independent public-pin tests of immutable directory lifetime and replacement."""

import argparse
import hashlib
import shutil
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from text_fixture import make_text_image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/tensor-lifetime")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-tensor-lifetime", source_inputs(), args.repair_of)
    error = None
    try:
        exp.run("verilator-version", ["verilator", "--version"], 30)
        exp.run("cxx-version", ["g++", "--version"], 30)
        exp.run("make-version", ["make", "--version"], 30)
        rows = []
        for model in (1, 2):
            for precision in (0, 1):
                image, _ = make_text_image(model, precision, 17)
                count = struct.unpack_from("<I", image, 24)[0]
                full = 16 + 16 * count
                stem = f"m{model}-p{precision}"
                original = exp.out / (stem + ".bin")
                original.write_bytes(image)
                malformed = bytearray(image)
                struct.pack_into("<I", malformed, 64 + (count - 1) * 64 + 44, 1)
                bad = exp.out / (stem + "-bad-tail.bin")
                bad.write_bytes(malformed)
                unordered = bytearray(image)
                unordered[64:128], unordered[128:192] = image[128:192], image[64:128]
                alternate = exp.out / (stem + "-unordered.bin")
                alternate.write_bytes(unordered)

                def case(label, index=0, reads=0, expected_error=0, reset=0,
                         invalidate=0, immutable=1, revoke=0, source=original,
                         base=0x100000, inject=0, invalidate_done=0):
                    data = source.read_bytes()
                    kind, layer, dtype, rank, _, offset, size = struct.unpack_from(
                        "<HHBBHQQ", data, 64 + 64 * index)
                    dims = struct.unpack_from("<4I", data, 88 + 64 * index)
                    stride = struct.unpack_from("<I", data, 104 + 64 * index)[0]
                    nrows, ncols = (dims[0], dims[1]) if rank == 2 else (1, dims[0])
                    rows.append([stem + "-" + label, str(source.relative_to(ROOT)),
                                 model, precision, base, kind, layer, offset, size,
                                 nrows, ncols, stride, dtype, expected_error, reads,
                                 reset, invalidate, immutable, revoke, inject,
                                 invalidate_done])

                case("first", reads=full, reset=int(model == 1 and precision == 0))
                case("hit")
                for index in range(1, 9):
                    case(f"fill-{index}", index=index, reads=index + 17)
                    case(f"hit-{index}", index=index)
                case("evicted", reads=17)
                case("same-address-invalidate", reads=full, invalidate=1)
                case("revoked-read", index=9, reads=26, expected_error=7, revoke=1)
                case("recertify-after-revoke", reads=full)
                case("drop-immutable-read", index=9, reads=26,
                     expected_error=7, revoke=2)
                case("recertify-after-drop", reads=full)
                case("invalidate-stalled-done", invalidate_done=1)
                case("recertify-after-done", reads=full)
                case("changed-base", reads=full, base=0x200000)
                case("restored-base", reads=full)
                case("bad-trailing-entry", reads=full, expected_error=5,
                     source=bad, invalidate=1)
                case("repair-after-error", reads=full)
                case("mutable", reads=full, immutable=0)
                case("mutable-same-address-mutation", reads=full, expected_error=5,
                     source=bad, immutable=0)
                case("immutable-after-mutable", reads=full)
                case("lookup-memory-error", index=9, reads=1, expected_error=2, inject=1)
                case("recertify-after-memory-error", reads=full)
                case("reset", reads=full, reset=1)
                exhaustive = full + 3 * count * (count - 1)
                case("unordered-first", reads=exhaustive, source=alternate, invalidate=1)
                case("unordered-hit", source=alternate)
                case("unordered-miss", index=10, reads=27, source=alternate)
        manifest = exp.out / "cases.txt"
        manifest.write_text("".join(" ".join(map(str, row)) + "\n" for row in rows))
        exp.receipt["fixtures"] = {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [manifest, *sorted(exp.out.glob("*.bin"))]}
        exp.receipt["expected_computed_before_observation"] = True
        exp.save()
        obj = exp.relative / "compile-obj"
        exp.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
            "--top-module", "anvil_en1_tensor_image", "--Mdir", str(obj),
            "-GCOMPACT=1", "-j", "2", "rtl/anvil_en1_tensor_image.sv",
            "rtl/anvil_en1_tensor_shape.sv", "rtl/anvil_en1_geometry.sv",
            str(ROOT / "tests/tensor_lifetime.cpp"),
        ], 1800)
        output = exp.run("simulation", [str(obj / "Vanvil_en1_tensor_image"),
                                      str(manifest.relative_to(ROOT))], 2400)
        if f"SUMMARY tensor_lifetime cases={len(rows)}" not in output:
            raise RuntimeError("incomplete immutable-lifetime comparisons")
        exp.receipt["comparison_cases"] = len(rows)
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
