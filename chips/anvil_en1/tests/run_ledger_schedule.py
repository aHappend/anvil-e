"""Discriminate ledger stimulus timing and simulator backend using public pins."""

import argparse
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/ledger-schedule")
    parser.add_argument("--repair-of")
    parser.add_argument("--simulator", choices=("both", "iverilog", "verilator", "cpp"),
                        default="both")
    parser.add_argument("--no-optimize", action="store_true",
                        help="discriminate compiled simulator optimization without RTL edits")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-ledger-schedule", source_inputs(), args.repair_of)
    failures = []
    try:
        for tool, option in (("iverilog", "-V"), ("vvp", "-V"),
                             ("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        sources = ["tests/ledger_schedule_tb.sv", "rtl/anvil_en1_allocation_ledger.sv"]
        for simulator in (("iverilog", "verilator") if args.simulator == "both"
                          else (args.simulator,)):
            try:
                if simulator == "iverilog":
                    binary = exp.relative / "ledger.vvp"
                    exp.run("icarus-compile", ["iverilog", "-g2012", "-Wall",
                                             "-s", "ledger_schedule_tb",
                                             "-o", str(binary), *sources], 1800)
                    output = exp.run("icarus-simulation", ["vvp", str(binary)], 600)
                elif simulator == "verilator":
                    obj = exp.relative / "compile-obj"
                    exp.run("verilator-compile", [
                        "verilator", "--binary", "--timing", "-Wno-fatal",
                        *(["-O0"] if args.no_optimize else []),
                        "--top-module", "ledger_schedule_tb", "--Mdir", str(obj),
                        "-j", "2", *sources], 1800)
                    output = exp.run("verilator-simulation",
                                     [str(obj / "Vledger_schedule_tb")], 2400)
                else:
                    obj = exp.relative / "compile-obj"
                    exp.run("cpp-compile", [
                        "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                        *(["-O0"] if args.no_optimize else []),
                        "--top-module", "anvil_en1_allocation_ledger", "--Mdir", str(obj),
                        "-j", "2", "rtl/anvil_en1_allocation_ledger.sv",
                        str(ROOT / "tests/ledger_schedule.cpp")], 1800)
                    output = exp.run("cpp-simulation",
                                     [str(obj / "Vanvil_en1_allocation_ledger")], 2400)
                if "SUMMARY ledger_schedule accepted=4 compared=4 failures=0" not in output:
                    raise RuntimeError("missing complete ledger comparison summary")
                exp.receipt.setdefault("backend_results", {})[simulator] = {
                    "status": "passed", "comparisons": 4,
                }
            except (OSError, RuntimeError, TimeoutError) as exc:
                failures.append(f"{simulator}: {exc}")
                exp.receipt.setdefault("backend_results", {})[simulator] = {
                    "status": "failed", "failure": str(exc),
                }
            exp.save()
        exp.receipt["scope"] = (
            "Four distinct live/shadow public reports, reset, consecutive observations "
            "and same-edge versus settled data stimulus; not full allocation acceptance.")
    except (OSError, RuntimeError, TimeoutError) as exc:
        failures.append(str(exc))
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish("; ".join(failures) if failures else None)


if __name__ == "__main__":
    raise SystemExit(main())
