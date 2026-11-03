"""Public tensor-directory validation, unordered compatibility and error retirement."""

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
    parser.add_argument("--out", default="evidence/preparation/tensor-image")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    experiment = Experiment(args.out, "verifier-tensor-image", source_inputs(), args.repair_of)
    error = None
    try:
        experiment.run("verilator-version", ["verilator", "--version"], 30)
        experiment.run("cxx-version", ["g++", "--version"], 30)
        experiment.run("make-version", ["make", "--version"], 30)
        experiment.run("iverilog-version", ["iverilog", "-V"], 30)
        experiment.run("vvp-version", ["vvp", "-V"], 30)
        cases = []

        def case(name, image, model=1, precision=0, expected_error=0, exact_reads=0,
                 image_base=0x100000, inject_error=0, reset_phase=0):
            image = bytes(image)
            path = experiment.out / (name + ".bin")
            path.write_bytes(image)
            kind, layer, tensor_type, _rank, _reserved, offset, length = (
                struct.unpack_from("<HHBBHQQ", image, 64))
            dimensions = struct.unpack_from("<4I", image, 88)
            stride = struct.unpack_from("<I", image, 104)[0]
            columns = dimensions[1] if _rank == 2 else dimensions[0]
            rows = dimensions[0] if _rank == 2 else 1
            cases.append([
                name, str(path.relative_to(ROOT)), model, precision, kind, layer,
                expected_error, offset, length, rows, columns, stride, tensor_type,
                exact_reads, image_base, inject_error, reset_phase,
            ])

        for model in (1, 2):
            for precision in (0, 1):
                image, _ = make_text_image(model, precision, 17)
                count = struct.unpack_from("<I", image, 24)[0]
                case(f"ordered-m{model}-p{precision}", image, model, precision,
                     exact_reads=16 + 16 * count)
        original, _ = make_text_image(1, 0, 17)
        count = struct.unpack_from("<I", original, 24)[0]
        unordered = bytearray(original)
        unordered[64:128], unordered[128:192] = original[128:192], original[64:128]
        case("unordered-directory", unordered,
             exact_reads=16 + 16 * count + 3 * count * (count - 1))
        # Retain sorted identities but move the first payload behind all other payloads.
        payload_order = bytearray(original)
        offset, length = struct.unpack_from("<QQ", payload_order, 72)
        struct.pack_into("<Q", payload_order, 72, len(payload_order))
        payload_order += original[offset:offset + length]
        struct.pack_into("<Q", payload_order, 16, len(payload_order))
        case("unordered-payloads", payload_order,
             exact_reads=16 + 16 * count + 3 * count * (count - 1))

        duplicate = bytearray(original)
        duplicate[192:256] = original[64:128]
        struct.pack_into("<Q", duplicate, 200, len(duplicate))
        duplicate += original[offset:offset + length]
        struct.pack_into("<Q", duplicate, 16, len(duplicate))
        case("nonadjacent-duplicate-disjoint", duplicate, expected_error=5)
        overlap = bytearray(original)
        struct.pack_into("<Q", overlap, 200, offset)
        case("nonadjacent-overlap", overlap, expected_error=5)
        for name, position, value, fmt in (
                ("header-reserved", 40, 1, "<I"),
                ("entry-reserved", 64 + 44, 1, "<I"),
                ("incorrect-length", 80, length + 4, "<Q"),
                ("directory-overlap", 72, 64, "<Q"),
                ("payload-outside-image", 72, len(original), "<Q"),
                ("payload-overflow", 72, 0xFFFFFFFFFFFFFFFC, "<Q"),
                ("incorrect-shape", 88, 31, "<I")):
            changed = bytearray(original)
            struct.pack_into(fmt, changed, position, value)
            case(name, changed, expected_error=5)
        case("image-base-overflow", original, expected_error=5,
             image_base=0xFFFFFFFFFFFFFFC0)
        case("memory-error", original, expected_error=2, exact_reads=21, inject_error=1)
        for phase in (1, 2, 3):
            case(f"reset-phase-{phase}", original, reset_phase=phase,
                 exact_reads=16 + 16 * count)
        manifest = experiment.out / "cases.txt"
        manifest.write_text("".join(" ".join(map(str, row)) + "\n" for row in cases))
        experiment.receipt["fixtures"] = {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in [manifest, *sorted(experiment.out.glob("*.bin"))]
        }
        experiment.receipt["expected_computed_before_observation"] = True
        experiment.save()
        executable = experiment.relative / "tensor-image.vvp"
        experiment.run("icarus-compile", [
            "iverilog", "-g2012", "-Wall", "-s", "tensor_image_tb",
            "-o", str(executable), "tests/tensor_image_tb.sv",
            "rtl/anvil_en1_tensor_image.sv", "rtl/anvil_en1_tensor_shape.sv",
            "rtl/anvil_en1_geometry.sv",
        ], 1800)
        smoke = experiment.run("icarus-smoke", [
            "vvp", str(executable),
            "+image=" + str(experiment.relative / "ordered-m1-p0.bin"),
        ], 600)
        if "SUMMARY tensor_image_icarus reads=8656 responses=8656 " not in smoke:
            raise RuntimeError("incomplete Icarus public-directory smoke")
        obj = experiment.relative / "compile-obj"
        experiment.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
            "--top-module", "anvil_en1_tensor_image", "--Mdir", str(obj),
            "-GCOMPACT=1", "-j", "2", "rtl/anvil_en1_tensor_image.sv",
            "rtl/anvil_en1_tensor_shape.sv", "rtl/anvil_en1_geometry.sv",
            str(ROOT / "tests/tensor_image.cpp"),
        ], 1800)
        output = experiment.run("simulation", [
            str(obj / "Vanvil_en1_tensor_image"), str(manifest.relative_to(ROOT)),
        ], 2400)
        if (f"SUMMARY tensor_image cases={len(cases)} resets=3" not in output or
                sum(line.startswith("CASE ") for line in output.splitlines()) != len(cases)):
            raise RuntimeError("incomplete directory comparison/coverage")
        experiment.receipt["comparison_cases"] = len(cases)
        experiment.receipt["reset_cases"] = 3
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = experiment.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return experiment.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
