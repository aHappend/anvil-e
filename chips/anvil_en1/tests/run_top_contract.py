"""Compact dual-simulator public top reset, rejection, CSR and DMA smoke."""

import argparse
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/top-contract")
    parser.add_argument("--repair-of")
    parser.add_argument("--simulator", choices=("both", "iverilog", "verilator"), default="both")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-top-contract", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("iverilog", "-V"), ("vvp", "-V"),
                             ("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        sources = ["tests/top_contract_tb.sv",
                   *[str(p.relative_to(ROOT)) for p in source_inputs()
                     if p.suffix == ".sv" and p.parent != ROOT / "tests"]]
        outputs = []
        if args.simulator != "verilator":
            binary = exp.relative / "top-contract.vvp"
            exp.run("icarus-compile", ["iverilog", "-g2012", "-Wall",
                                     "-s", "top_contract_tb", "-o", str(binary),
                                     *sources], 1800)
            outputs.append(exp.run("icarus-smoke", ["vvp", str(binary)], 600))
        if args.simulator != "iverilog":
            obj = exp.relative / "compile-obj"
            exp.run("verilator-compile", [
                "verilator", "--binary", "--timing", "-Wno-fatal",
                "--top-module", "top_contract_tb", "--Mdir", str(obj),
                "-j", "2", *sources], 1800)
            outputs.append(exp.run("verilator-smoke", [str(obj / "Vtop_contract_tb")], 2400))
        markers = [re.search(r"SUMMARY top_contract ([^\n]+)", text) for text in outputs]
        if not all(markers):
            raise RuntimeError("missing public-top smoke comparisons")
        observed = [dict((k, int(v)) for k, v in
                         (field.split("=") for field in marker.group(1).split()))
                    for marker in markers]
        for counts in observed:
            if (counts["rejections"] != 17 or counts["csr_reads"] != 2 or
                    counts["memory_errors"] != 1 or counts["canceled_requests"] != 1 or
                    counts["comparisons"] <= 0 or counts["reset_checks"] < 4 or
                    counts["cycles"] > 500000):
                raise RuntimeError("incomplete public-top smoke coverage")
        if len(observed) == 2 and observed[0] != observed[1]:
            raise RuntimeError("dual-simulator public-top smoke differs")
        exp.receipt["observed_counts"] = observed[0]
        exp.receipt["simulator"] = args.simulator
        exp.receipt["scope"] = "Reset/protocol smoke; no completed neural inference"
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
