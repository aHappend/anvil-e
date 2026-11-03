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
from reader_fixtures import directory_image, input_shapes, text_shapes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/tensor-lifetime")
    parser.add_argument("--repair-of")
    parser.add_argument("--production", action="store_true",
                        help="validate production directory geometry with virtual payload extents")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-tensor-lifetime", source_inputs(), args.repair_of)
    error = None
    try:
        exp.run("verilator-version", ["verilator", "--version"], 30)
        exp.run("cxx-version", ["g++", "--version"], 30)
        exp.run("make-version", ["make", "--version"], 30)
        rows = []
        images = exp.out / "checkpoint-images"
        images.mkdir()
        for model in (1, 2):
            for precision in (0, 1):
                if args.production:
                    image = directory_image(model, precision, text_shapes(model))
                else:
                    image, _ = make_text_image(model, precision, 17)
                count = struct.unpack_from("<I", image, 24)[0]
                full = 16 + 16 * count
                stem = f"m{model}-p{precision}"
                original = images / (stem + ".bin")
                original.write_bytes(image)
                malformed = bytearray(image)
                struct.pack_into("<I", malformed, 64 + (count - 1) * 64 + 44, 1)
                bad = images / (stem + "-bad-tail.bin")
                bad.write_bytes(malformed)
                unordered = bytearray(image)
                unordered[64:128], unordered[128:192] = image[128:192], image[64:128]
                alternate = images / (stem + "-unordered.bin")
                alternate.write_bytes(unordered)

                def case(label, index=0, reads=0, expected_error=0, reset=0,
                         invalidate=0, immutable=1, revoke=0, source=original,
                         base=0x100000, inject=0, invalidate_done=0,
                         request_layer=None, request_kind=None):
                    data = source.read_bytes()
                    kind, layer, dtype, rank, _, offset, size = struct.unpack_from(
                        "<HHBBHQQ", data, 64 + 64 * index)
                    dims = struct.unpack_from("<4I", data, 88 + 64 * index)
                    stride = struct.unpack_from("<I", data, 104 + 64 * index)[0]
                    nrows, ncols = (dims[0], dims[1]) if rank == 2 else (1, dims[0])
                    rows.append([stem + "-" + label, str(source.relative_to(ROOT)),
                                 model, precision, base,
                                 kind if request_kind is None else request_kind,
                                 layer if request_layer is None else request_layer, offset, size,
                                 nrows, ncols, stride, dtype, expected_error, reads,
                                 reset, invalidate, immutable, revoke, inject,
                                 invalidate_done, 0, 0, 0])

                case("first", reads=full, reset=int(model == 1 and precision == 0))
                case("hit")
                case("reject-global-sentinel-alias", expected_error=5, request_layer=63)
                case("recertify-after-invalid-key", reads=full)
                case("invalidate-hit-capture", expected_error=7, revoke=3)
                case("recertify-after-hit-invalidate", reads=full)
                case("drop-immutable-hit-capture", expected_error=7, revoke=4)
                case("recertify-after-hit-drop", reads=full)
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
                case("restore-sorted", reads=full, invalidate=1)
                # The packed layer key must never admit a truncated invalid layer.
                for invalid_layer in (64, 256, 0xFFC0):
                    case(f"reject-layer-{invalid_layer}", index=5, reads=0,
                         request_layer=invalid_layer, expected_error=5)
                    case(f"recertify-after-layer-{invalid_layer}", index=5, reads=full)
                case("reject-kind-high-bits", index=5, reads=0,
                     request_kind=0x8100, expected_error=5)
                case("recertify-after-kind", index=5, reads=full)
        if args.production:
            for model in (1, 2):
                for audio in (0, 1):
                    for items in (1, 17, 65535, 65536, 65537, 0x1000001):
                        image = directory_image(model, 0, input_shapes(audio, items), 3)
                        name = f"input-m{model}-a{audio}-n{items}"
                        path = images / (name + ".bin")
                        path.write_bytes(image)
                        for index in (0, 1):
                            kind, layer, dtype, rank, _, offset, size = struct.unpack_from(
                                "<HHBBHQQ", image, 64 + 64 * index)
                            dims = struct.unpack_from("<4I", image, 88 + 64 * index)
                            stride = struct.unpack_from("<I", image, 104 + 64 * index)[0]
                            nrows, ncols = (dims[0], dims[1]) if rank == 2 else (1, dims[0])
                            for hit in (0, 1):
                                reads = 0 if hit else (48 if index == 0 else 18)
                                rows.append([
                                    name + f"-i{index}-hit{hit}", str(path.relative_to(ROOT)),
                                    model, 0, 0x100000, kind, layer, offset, size,
                                    nrows, ncols, stride, dtype, 0, reads,
                                    0, 0, 1, 0, 0, 0, 3, audio, items])
        manifest = exp.out / "cases.txt"
        manifest.write_text("".join(" ".join(map(str, row)) + "\n" for row in rows))
        exp.receipt["fixtures"] = {
            str(p.relative_to(exp.out)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [manifest, *sorted(images.glob("*.bin"))]}
        exp.receipt["expected_computed_before_observation"] = True
        exp.receipt["scope"] = (
            "Public reader key/geometry/length/lifetime behavior, not payload arithmetic "
            "or integrated allocation. Production fixtures contain only directories; "
            "validated payload extents are virtual and must never be read.")
        exp.receipt["production_geometry"] = args.production
        exp.save()
        obj = exp.relative / "compile-obj"
        exp.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
            "--top-module", "anvil_en1_tensor_image", "--Mdir", str(obj),
            f"-GCOMPACT={int(not args.production)}", "-j", "2", "rtl/anvil_en1_tensor_image.sv",
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
