"""Bounded compiler profile, not a neural completion or acceptance check."""

import argparse
import hashlib
import os
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
    parser.add_argument("--hierarchical", action="store_true")
    parser.add_argument("--threads", type=int, choices=(1, 2, 4), default=1)
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
        exp.receipt["hierarchical_arithmetic"] = args.hierarchical
        exp.receipt["simulation_threads"] = args.threads
        exp.receipt["scope"] = (
            "200000-cycle public-top compiler profile with real weights and input; "
            "an incomplete numerical job is expected, never counted as neural completion.")
        exp.save()
        obj = exp.relative / "compile-obj"
        compiler = ["verilator"]
        if args.hierarchical:
            root = exp.run("verilator-root", [
                "verilator", "--getenv", "VERILATOR_ROOT"], 30).strip()
            binary = shutil.which("verilator_bin")
            if not root or binary is None:
                raise RuntimeError("hierarchical profiling requires the installed Verilator binary")
            compiler = ["env", "VERILATOR_BIN=" + os.path.relpath(binary, root), binary]
        sources = [str(path.relative_to(ROOT)) for path in source_inputs()
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        top = "anvil_en1_top"
        parameter_args = [f"-G{name}={value}" for name, value in parameters.items()]
        if args.hierarchical:
            # Verilator 5.020 forwards top-level -G overrides into child builds.
            # A pure structural wrapper freezes the same legal elaboration
            # without changing ports, clocks, datapaths or observation timing.
            declaration = (ROOT / "rtl/anvil_en1_top.sv").read_text()
            ports = declaration.split(") (", 1)[1].split(");", 1)[0]
            wrapper = exp.out / "profile_top.sv"
            wrapper.write_text(
                "module profile_top (" + ports + ");\n"
                "anvil_en1_top #(" +
                ", ".join(f".{name}({value})" for name, value in parameters.items()) +
                ") product (.*);\nendmodule\n")
            exp.receipt["structural_wrapper_sha256"] = hashlib.sha256(
                wrapper.read_bytes()).hexdigest()
            top = "profile_top"
            parameter_args = ["--prefix", "Vanvil_en1_top", str(wrapper.relative_to(ROOT))]
            exp.save()
        exp.run("compile", [
            *compiler, "--cc", "--exe", "--build", "-O3", "-Wno-fatal",
            "--top-module", top, "--Mdir", str(obj),
            "--threads", str(args.threads),
            "-j", "2", "-CFLAGS", "-O3 -pg", "-LDFLAGS", "-pg",
            *(["--hierarchical", "tests/simulation_hierarchy.vlt"]
              if args.hierarchical else []),
            *parameter_args,
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
