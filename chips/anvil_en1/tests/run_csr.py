"""Public CSR banking, atomic pairs, snapshots, saturation and clear sensitivity."""

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/csr")
    parser.add_argument("--defect", action="store_true")
    parser.add_argument("--simulator", choices=("both", "verilator"), default="both")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    experiment = Experiment(args.out, "verifier-csr", source_inputs(), args.repair_of)
    error = None
    try:
        experiment.run("verilator-version", ["verilator", "--version"], 30)
        experiment.run("cxx-version", ["g++", "--version"], 30)
        experiment.run("make-version", ["make", "--version"], 30)
        if args.simulator == "both":
            experiment.run("iverilog-version", ["iverilog", "-V"], 30)
            experiment.run("vvp-version", ["vvp", "-V"], 30)
            binary = experiment.relative / "csr.vvp"
            experiment.run("icarus-compile", [
                "iverilog", "-g2012", "-Wall", "-s", "csr_tb", "-o", str(binary),
                "tests/csr_tb.sv", "rtl/anvil_en1_csr_perf.sv",
            ], 1800)
            smoke = experiment.run("icarus-smoke", ["vvp", str(binary)], 600)
            if "SUMMARY csr_icarus comparisons=9 reset_stalled_response=1" not in smoke:
                raise RuntimeError("incomplete four-state CSR smoke")
        variants = [("original", "rtl/anvil_en1_csr_perf.sv")]
        if args.defect:
            original = (ROOT / variants[0][1]).read_text()
            needle = "if (clear_counters)\n                        counters[INDEX] <= 0;"
            if original.count(needle) != 1:
                raise RuntimeError("CSR clear mutation site not unique")
            mutant = experiment.out / "csr_clear_priority.sv"
            mutant.write_text(original.replace(needle,
                "if (clear_counters && !selected_event)\n                        counters[INDEX] <= 0;"))
            variants.append(("clear-priority", str(mutant.relative_to(ROOT))))
            experiment.receipt["mutation"] = {
                "path": str(mutant.relative_to(ROOT)),
                "sha256": hashlib.sha256(mutant.read_bytes()).hexdigest(),
                "intended_assertion": "CSR_CLEAR_PRIORITY",
            }
        for name, source in variants:
            obj = experiment.relative / (name + "-compile-obj")
            experiment.run(name + "-compile", [
                "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                "--top-module", "anvil_en1_csr_perf", "--Mdir", str(obj),
                "-j", "2", source, str(ROOT / "tests/csr.cpp"),
            ], 1800)
            output = experiment.run(name + "-simulation", [
                str(obj / "Vanvil_en1_csr_perf"),
            ], 2400, (0,) if name == "original" else (1,))
            if name == "original":
                if "SUMMARY csr transactions=" not in output or "clear_coincidences=1 " not in output:
                    raise RuntimeError("incomplete CSR comparison coverage")
                experiment.receipt["summary"] = output.strip()
            else:
                stderr = (experiment.out / (name + "-simulation.stderr.txt")).read_text()
                if "FAIL CSR_CLEAR_PRIORITY" not in stderr:
                    raise RuntimeError("mutant was not rejected by clear-priority assertion")
                experiment.record_rejection(
                    "csr-clear-priority", "CSR_CLEAR_PRIORITY",
                    ("original-compile", "original-simulation"),
                    ("clear-priority-compile", "clear-priority-simulation"))
            shutil.rmtree(ROOT / obj)
        experiment.receipt["mutant_rejected"] = args.defect
        experiment.receipt["simulator"] = args.simulator
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        for name in ("original", "clear-priority"):
            obj = experiment.out / (name + "-compile-obj")
            if obj.exists():
                shutil.rmtree(obj)
    return experiment.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
