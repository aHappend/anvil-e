"""Disposable wrong-anchor defect; requires a public owner assertion rejection."""

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/cache-defect")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    experiment = Experiment(args.out, "verifier-cache-defect-preparation",
                            source_inputs(), args.repair_of)
    error = None
    try:
        experiment.run("verilator-version", ["verilator", "--version"], 30)
        original = (ROOT / "rtl/anvil_en1_geometry.sv").read_text()
        needle = "1: anchor_owner = is_global ? 8'd14 : 8'd13;"
        if original.count(needle) != 1:
            raise RuntimeError("mutation site is not unique")
        mutation = original.replace(needle, "1: anchor_owner = is_global ? 8'd13 : 8'd13;")
        mutant = experiment.out / "wrong_anchor.sv"
        mutant.write_text(mutation)
        experiment.receipt["mutation"] = {
            "kind": "wrong-anchor",
            "path": str(mutant.relative_to(ROOT)),
            "sha256": hashlib.sha256(mutant.read_bytes()).hexdigest(),
            "intended_assertion": "OWNER_OR_ADDRESS",
        }
        for name, geometry in (("original", "rtl/anvil_en1_geometry.sv"),
                               ("wrong-anchor", str(mutant.relative_to(ROOT)))):
            obj = experiment.relative / (name + "-compile-obj")
            experiment.run(name + "-compile",
                           ["verilator", "--binary", "--timing", "-Wno-fatal",
                            "--top-module", "cache_tb", "--Mdir", str(obj),
                            "-j", "2", "-GCAPACITY=3", "tests/cache_tb.sv",
                            "rtl/anvil_en1_kv_shared_cache.sv", geometry], 1800)
            output = experiment.run(name + "-simulation", [str(obj / "Vcache_tb")],
                                    600, (0,) if name == "original" else (1, -6))
            if name == "original":
                if "SUMMARY cache capacity=3 " not in output:
                    raise RuntimeError("unmodified cache failed to complete comparisons")
            elif "OWNER_OR_ADDRESS" not in output:
                raise RuntimeError("mutant was not rejected by its intended owner assertion")
            shutil.rmtree(ROOT / obj)
        experiment.receipt["defect_sensitivity"] = {
            "unmodified_completed": True, "mutant_rejected": True,
            "assertion": "OWNER_OR_ADDRESS",
        }
        experiment.record_rejection(
            "wrong-anchor", "OWNER_OR_ADDRESS",
            ("original-compile", "original-simulation"),
            ("wrong-anchor-compile", "wrong-anchor-simulation"))
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        for name in ("original", "wrong-anchor"):
            obj = experiment.out / (name + "-compile-obj")
            if obj.exists():
                shutil.rmtree(obj)
    return experiment.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
