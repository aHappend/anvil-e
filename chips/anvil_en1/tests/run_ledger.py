"""Public allocation-ledger smoke, including its interpreted simulator backend."""

import argparse
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/ledger")
    parser.add_argument("--repair-of")
    parser.add_argument("--simulator", choices=("iverilog", "verilator", "cpp"),
                        default="iverilog")
    parser.add_argument("--split-schedule", action="store_true")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-ledger", source_inputs(), args.repair_of)
    error = None
    try:
        exp.run("simulator-version",
                ["iverilog" if args.simulator == "iverilog" else "verilator", "-V"], 30)
        sources = ["tests/ledger_tb.sv", "rtl/anvil_en1_allocation_ledger.sv"]
        if args.simulator == "iverilog":
            exp.run("vvp-version", ["vvp", "-V"], 30)
            binary = exp.relative / "ledger.vvp"
            exp.run("compile", ["iverilog", "-g2012", "-Wall", "-s", "ledger_tb",
                                "-o", str(binary), *sources], 1800)
            output = exp.run("simulation", ["vvp", str(binary), "+controller=512"], 600)
        elif args.simulator == "verilator":
            exp.run("cxx-version", ["g++", "--version"], 30)
            exp.run("make-version", ["make", "--version"], 30)
            obj = exp.relative / "compile-obj"
            exp.run("compile", ["verilator", "--binary", "--timing", "-Wno-fatal",
                                "--top-module", "ledger_tb", "--Mdir", str(obj),
                                "-j", "2",
                                *(["tests/simulation_schedule.vlt"] if
                                  args.split_schedule else []), *sources], 1800)
            output = exp.run("simulation", [str(obj / "Vledger_tb"), "+controller=512"], 2400)
        else:
            exp.run("cxx-version", ["g++", "--version"], 30)
            exp.run("make-version", ["make", "--version"], 30)
            obj = exp.relative / "compile-obj"
            exp.run("compile", ["verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                                "--top-module", "anvil_en1_allocation_ledger",
                                "--Mdir", str(obj), "-j", "2",
                                *(["tests/simulation_schedule.vlt"] if
                                  args.split_schedule else []),
                                "rtl/anvil_en1_allocation_ledger.sv",
                                str(ROOT / "tests/ledger.cpp")], 1800)
            output = exp.run("simulation",
                             [str(obj / "Vanvil_en1_allocation_ledger")], 2400)
        if "SUMMARY ledger accepted=1 compared=1" not in output:
            raise RuntimeError("ledger smoke did not compare its complete public report")
        exp.receipt["comparison_count"] = 1
        exp.receipt["scope"] = "One public-ledger report, not integrated allocation coverage"
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
