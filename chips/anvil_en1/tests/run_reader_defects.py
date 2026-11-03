"""Disposable reader defects must fail the independent public geometry oracle."""

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/reader-defects")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-reader-defects", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        output = exp.run("baseline", [
            sys.executable, "tests/run_tensor_lifetime.py", "--production",
            "--out", str(exp.relative / "baseline")], 2400)
        result = json.loads(output.strip().splitlines()[-1])
        receipt_path = Path(result["receipt"])
        if receipt_path.is_absolute() or ".." in receipt_path.parts:
            raise RuntimeError("baseline returned a non-project-relative receipt")
        baseline = json.loads((ROOT / receipt_path).read_text())
        if baseline["status"] != "passed" or baseline["comparison_cases"] <= 0:
            raise RuntimeError("unmodified reader did not complete its public comparisons")
        exp.receipt["unmodified_receipt"] = str(receipt_path)
        manifest = receipt_path.parent / "cases.txt"
        original_path = ROOT / "rtl/anvil_en1_tensor_image.sv"
        original = original_path.read_text()
        mutations = (
            ("truncated-hit-length", "output_bytes <= hit_bytes;",
             "output_bytes <= {32'd0, hit_bytes[31:0]};"),
            ("unchecked-layer-key",
             "!requested_valid || base_hold[1:0] != 0 ||",
             "1'b0 || base_hold[1:0] != 0 ||"),
        )
        exp.receipt["mutations"] = []
        for name, needle, replacement in mutations:
            if original.count(needle) != 1:
                raise RuntimeError("mutation site is not unique: " + name)
            path = exp.out / (name + ".sv")
            path.write_text(original.replace(needle, replacement))
            entry = {
                "name": name, "source": str(path.relative_to(ROOT)),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "intended_assertion": "DIRECTORY_RESULT",
            }
            exp.receipt["mutations"].append(entry)
            exp.save()
            obj = exp.relative / "compile-obj"
            exp.run(name + "-compile", [
                "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                "--top-module", "anvil_en1_tensor_image", "--Mdir", str(obj),
                "-GCOMPACT=0", "-j", "2", str(path.relative_to(ROOT)),
                "rtl/anvil_en1_tensor_shape.sv", "rtl/anvil_en1_geometry.sv",
                str(ROOT / "tests/tensor_lifetime.cpp")], 1800)
            exp.run(name + "-simulation", [str(obj / "Vanvil_en1_tensor_image"),
                                           str(manifest)], 2400, (1,))
            stderr = (exp.out / (name + "-simulation.stderr.txt")).read_text()
            if "FAIL " not in stderr or ": DIRECTORY_RESULT" not in stderr:
                raise RuntimeError(name + " failed outside its intended public assertion")
            entry["rejected_by_intended_assertion"] = True
            entry["diagnostic"] = stderr.strip()
            shutil.rmtree(ROOT / obj)
        if hashlib.sha256(original_path.read_bytes()).hexdigest() != (
                exp.receipt["source_sha256"]["rtl/anvil_en1_tensor_image.sv"]):
            raise RuntimeError("original reader changed during disposable mutation checks")
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
