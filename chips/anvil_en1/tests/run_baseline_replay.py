"""Reproduce a baseline transactor failure with byte-bound, frozen reference inputs."""

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/baseline-replay")
    parser.add_argument("--fixtures-from", required=True)
    parser.add_argument("--repair-of")
    parser.add_argument("--defects", action="store_true")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-baseline-transactor-repair", source_inputs(),
                     args.repair_of or args.fixtures_from)
    error = None
    try:
        receipt_path = Path(args.fixtures_from)
        if receipt_path.is_absolute() or ".." in receipt_path.parts:
            raise ValueError("fixture receipt must be project-relative")
        previous = json.loads((ROOT / receipt_path).read_text())
        for source in ("tests/text_fixture.py", "tests/text_reference.py",
                       "tests/numerical_reference.py", "tests/run_baseline.py"):
            if hashlib.sha256((ROOT / source).read_bytes()).hexdigest() != (
                    previous["source_sha256"][source]):
                raise ValueError("frozen baseline generator changed: " + source)
        for name, digest in previous["fixtures"].items():
            path = receipt_path.parent / name
            if Path(name).name != name or hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != digest:
                raise ValueError("frozen fixture changed: " + name)
        exp.receipt["frozen_fixtures"] = previous["fixtures"]
        exp.receipt["scope"] = "Transactor repair reproduction, not candidate traffic acceptance."
        exp.save()
        for tool, option in (("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        obj = exp.relative / "compile-obj"
        variants = [("original", Path("tests/kv_baseline.sv"), None)]
        if args.defects:
            original = (ROOT / "tests/kv_baseline.sv").read_text()
            exp.receipt["mutations"] = []
            for name, before, after, assertion in (
                    ("omitted-logical-copy", "model_hold == 1 ? 35 : 42;",
                     "model_hold == 1 ? 34 : 41;", "BASELINE_ADDRESS_VALUE"),
                    ("wrong-owner-value", "model_hold == 1 ? 14 : 23;",
                     "model_hold == 1 ? 13 : 22;", "BASELINE_OWNER_VALUE_SOURCE")):
                if original.count(before) != 1:
                    raise RuntimeError("baseline mutation site is not unique: " + name)
                path = exp.relative / (name + ".sv")
                (ROOT / path).write_text(original.replace(before, after))
                variants.append((name, path, assertion))
                exp.receipt["mutations"].append({
                    "name": name, "source": str(path),
                    "sha256": hashlib.sha256((ROOT / path).read_bytes()).hexdigest(),
                    "intended_assertion": assertion})
        exp.save()
        for name, source, assertion in variants:
            exp.run(name + "-compile", [
                "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                "--top-module", "kv_baseline", "--Mdir", str(obj),
                "-j", "2", str(source), str(ROOT / "tests/kv_baseline.cpp")], 1800)
            output = exp.run(name + "-simulation", [str(obj / "Vkv_baseline"),
                                                   str(receipt_path.parent / "cases.txt")],
                             2400, (1,) if assertion else (0,))
            if assertion:
                stderr = (exp.out / (name + "-simulation.stderr.txt")).read_text()
                if "FAIL " + assertion not in stderr:
                    raise RuntimeError("baseline defect missed intended assertion: " + name)
            else:
                if "SUMMARY baseline cases=" not in output:
                    raise RuntimeError("baseline did not complete frozen command scoreboards")
                exp.receipt["summary"] = output.strip()
            shutil.rmtree(ROOT / obj)
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
