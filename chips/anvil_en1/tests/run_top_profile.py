"""Bounded compiler profile, not a neural completion or acceptance check."""

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from simulation_config import COMPACT_PARENT
from text_fixture import make_text_image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/top-profile")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-top-throughput-profile", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version"), ("gprof", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        images = exp.out / "checkpoint-images"
        images.mkdir()
        image, _ = make_text_image(1, 0, 17)
        path = images / "text.bin"
        path.write_bytes(image)
        exp.receipt["fixtures"] = {
            str(path.relative_to(exp.out)): hashlib.sha256(image).hexdigest()}
        parameters = dict(COMPACT=1, RESIDENT_ENTRIES=64, FORCE_FALLBACK=0,
                          **COMPACT_PARENT)
        exp.receipt["parameters"] = parameters
        exp.receipt["scope"] = (
            "200000-cycle public-top compiler profile with real weights and input; "
            "an incomplete numerical job is expected, never counted as neural completion.")
        exp.save()
        obj = exp.relative / "compile-obj"
        sources = [str(path.relative_to(ROOT)) for path in source_inputs()
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        exp.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-O3", "-Wno-fatal",
            "--top-module", "anvil_en1_top", "--Mdir", str(obj),
            "-j", "2", "-CFLAGS", "-O3 -pg", "-LDFLAGS", "-pg",
            *[f"-G{name}={value}" for name, value in parameters.items()],
            "tests/simulation_schedule.vlt", *sources,
            str(ROOT / "tests/top_smoke.cpp")], 1800)
        executable = obj / "Vanvil_en1_top"
        output = exp.run("simulation", [
            "env", "GMON_OUT_PREFIX=" + str(exp.relative / "gmon"),
            str(executable), str(path.relative_to(ROOT)), "1", "0", "17", "200000"],
            2400, (1,))
        stderr = (exp.out / "simulation.stderr.txt").read_text()
        if ("INCOMPLETE cycle_limit=200000 " not in output or
                "PERFORMANCE cycles=200000 " not in output or
                "FAIL cycle limit reached without complete top result" not in stderr):
            raise RuntimeError("profile failed before its intended bounded observation")
        profiles = list(exp.out.glob("gmon.*"))
        if len(profiles) != 1:
            raise RuntimeError("missing or ambiguous compiler profile output")
        exp.run("profile", ["gprof", "-b", "--flat-profile", str(executable),
                            str(profiles[0].relative_to(ROOT))], 2400)
        exp.receipt["performance"] = next(
            line for line in output.splitlines() if line.startswith("PERFORMANCE "))
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
