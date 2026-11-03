"""Time-zero/active-X and compact owner numerical smoke under Icarus."""

import argparse
import hashlib
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from numerical_reference import encode
from run_owner_tile import expected_vector
from text_fixture import make_text_image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/owner-icarus")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-owner-icarus", source_inputs(), args.repair_of)
    error = None
    try:
        for tool in ("iverilog", "vvp"):
            exp.run(tool + "-version", [tool, "-V"], 30)
        images = exp.out / "checkpoint-images"
        images.mkdir()
        image, tensors = make_text_image(1, 0, 17)
        source, vector = expected_vector(tensors, 13, 0, 17, 0, False)
        expected = vector[0] | vector[1] << 16
        image_path, source_path = images / "weights.hex", images / "source.hex"
        image_path.write_text("".join(f"{word:02x}\n" for word in image))
        source_path.write_text("".join(
            f"{encode(value, exponent_bits=8, fraction_bits=7):04x}\n"
            for value in source))
        exp.receipt["fixtures"] = {
            str(path.relative_to(exp.out)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (image_path, source_path)}
        exp.receipt["expected_pair"] = expected
        exp.receipt["expected_computed_before_observation"] = True
        exp.save()
        sources = [str(path.relative_to(ROOT)) for path in source_inputs()
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        binary = exp.relative / "owner.vvp"
        exp.run("compile", ["iverilog", "-g2012", "-Wall", "-s", "owner_tile_tb",
                            "-o", str(binary), "tests/owner_tile_tb.sv", *sources], 600)
        output = exp.run("simulation", [
            "vvp", str(binary), "+image=" + str(image_path.relative_to(ROOT)),
            "+source=" + str(source_path.relative_to(ROOT)),
            "+image_bytes=" + str(len(image)), "+expected=" + f"{expected:08x}"], 600)
        if "SUMMARY owner_icarus pairs=1 projections=4 " not in output:
            raise RuntimeError("incomplete Icarus public-owner numerical smoke")
        exp.receipt["summary"] = output.strip()
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
