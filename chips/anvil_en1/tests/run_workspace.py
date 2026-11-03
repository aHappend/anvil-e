"""Public workspace visibility/allocation regression and production synthesis."""

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
    parser.add_argument("--out", default="evidence/preparation/workspace")
    parser.add_argument("--repair-of")
    parser.add_argument("--synthesis", action="store_true")
    parser.add_argument("--defects", action="store_true")
    args = parser.parse_args()
    if args.synthesis and args.defects:
        parser.error("--defects is a simulation option")
    exp = Experiment(args.out, "verifier-workspace", source_inputs(), args.repair_of)
    error = None
    try:
        if args.synthesis:
            exp.run("yosys-version", ["yosys", "-V"], 30)
            script = exp.out / "synthesis.ys"
            script.write_text(
                "read_verilog -sv rtl/anvil_en1_geometry.sv "
                "rtl/anvil_en1_replay_workspace.sv\n"
                "hierarchy -check -top anvil_en1_replay_workspace\n"
                "proc\nopt_expr\nopt_clean\ncheck -assert -noinit\n"
                "memory -nomap\nopt_clean\ncheck -assert -noinit\n"
                "select -assert-none t:$dlatch t:$adlatch t:$div t:$mod\n"
                f"stat\nwrite_json {exp.relative}/netlist.json\n")
            exp.run("synthesis", ["yosys", "-Q", "-T", "-s",
                                 str(script.relative_to(ROOT))], 2400)
            netlist = json.loads((exp.out / "netlist.json").read_text())
            cells = [c for m in netlist["modules"].values() for c in m.get("cells", {}).values()]
            types = [c["type"] for c in cells]
            if not any(t.startswith("$mem") for t in types):
                raise RuntimeError("workspace lost tag memories")
            if not any(t in ("$adff", "$dff", "$adffe", "$dffe") for t in types):
                raise RuntimeError("workspace lost substantive sequential state")
            if any(t in ("$dlatch", "$adlatch", "$div", "$mod") for t in types):
                raise RuntimeError("workspace retained forbidden cells")
            exp.receipt["structural_results"] = {
                "cells": len(cells), "modules": len(netlist["modules"]),
                "memory_cells": sum(t.startswith("$mem") for t in types)}
        else:
            exp.run("verilator-version", ["verilator", "--version"], 30)
            exp.run("cxx-version", ["g++", "--version"], 30)
            exp.run("make-version", ["make", "--version"], 30)
            exp.run("iverilog-version", ["iverilog", "-V"], 30)
            exp.run("vvp-version", ["vvp", "-V"], 30)
            binary = exp.relative / "workspace.vvp"
            exp.run("icarus-compile", ["iverilog", "-g2012", "-Wall",
                                     "-s", "workspace_tb", "-o", str(binary),
                                     "tests/workspace_tb.sv",
                                     "rtl/anvil_en1_replay_workspace.sv",
                                     "rtl/anvil_en1_geometry.sv"], 1800)
            smoke = exp.run("icarus-smoke", ["vvp", str(binary)], 600)
            if "SUMMARY workspace_icarus comparisons=16 " not in smoke:
                raise RuntimeError("incomplete Icarus workspace comparisons")
            obj = exp.relative / "compile-obj"
            exp.run("compile", [
                "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                "--top-module", "anvil_en1_replay_workspace", "--Mdir", str(obj),
                "-GCOMPACT=1", "-j", "2", "rtl/anvil_en1_replay_workspace.sv",
                "rtl/anvil_en1_geometry.sv", str(ROOT / "tests/workspace.cpp")], 1800)
            output = exp.run("simulation", [str(obj / "Vanvil_en1_replay_workspace")], 2400)
            if "SUMMARY workspace cases=" not in output:
                raise RuntimeError("incomplete workspace comparisons")
            exp.receipt["simulation_summary"] = output.strip()
            shutil.rmtree(ROOT / obj)
            if args.defects:
                original = (ROOT / "rtl/anvil_en1_replay_workspace.sv").read_text()
                mutations = (
                    ("partial-visible", "if (pair_write_last)\n                                occupied <= 1;",
                     "if (1'b1)\n                                occupied <= 1;",
                     "UNFILLED_VECTOR_VISIBILITY"),
                    ("missing-live-frame-allocation", "live_frames + live_scalars + live_memos",
                     "live_frames + live_memos", "ALLOCATION_LEDGER"),
                )
                exp.receipt["mutations"] = []
                for name, needle, replacement, assertion in mutations:
                    if original.count(needle) != 1:
                        raise RuntimeError(f"mutation site is not unique: {name}")
                    source = exp.out / (name + ".sv")
                    source.write_text(original.replace(needle, replacement))
                    exp.receipt["mutations"].append({
                        "name": name, "path": str(source.relative_to(ROOT)),
                        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "intended_assertion": assertion})
                    exp.save()
                    exp.run(name + "-compile", [
                        "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                        "--top-module", "anvil_en1_replay_workspace", "--Mdir", str(obj),
                        "-GCOMPACT=1", "-j", "2", str(source.relative_to(ROOT)),
                        "rtl/anvil_en1_geometry.sv", str(ROOT / "tests/workspace.cpp")], 1800)
                    exp.run(name + "-simulation",
                            [str(obj / "Vanvil_en1_replay_workspace")], 2400, (1,))
                    stderr = (exp.out / (name + "-simulation.stderr.txt")).read_text()
                    if "FAIL " + assertion not in stderr:
                        raise RuntimeError(f"mutant missed its intended assertion: {name}")
                    exp.receipt["mutations"][-1]["rejected_by_intended_assertion"] = True
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
