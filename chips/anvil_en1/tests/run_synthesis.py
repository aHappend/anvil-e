"""Bounded hierarchy/process/memory synthesis; no FPGA timing or mapping claims."""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from simulation_config import COMPACT_PARENT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/synthesis")
    parser.add_argument("--top", choices=("anvil_en1_top", "anvil_en1_kv_shared_cache",
                                        "anvil_en1_fp32"), default="anvil_en1_top")
    parser.add_argument("--repair-of")
    parser.add_argument("--compact-parent", action="store_true",
                        help="bound only model-0 parameters; retain native production geometry")
    args = parser.parse_args()
    inputs = source_inputs()
    experiment = Experiment(args.out, "verifier-synthesis-preparation", inputs, args.repair_of)
    error = None
    try:
        experiment.run("yosys-version", ["yosys", "-V"], 30)
        sources = [str(path.relative_to(ROOT)) for path in inputs
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        script = experiment.out / "synthesis.ys"
        parameters = {}
        if args.compact_parent:
            if args.top != "anvil_en1_top":
                raise ValueError("--compact-parent requires anvil_en1_top")
            parameters = COMPACT_PARENT
        experiment.receipt["parameters"] = parameters
        experiment.receipt["native_compact"] = False
        hierarchy = f"hierarchy -check -top {args.top}" + "".join(
            f" -chparam {name} {value}" for name, value in parameters.items())
        script.write_text(
            "read_verilog -sv -defer " + " ".join(sources) + "\n" +
            hierarchy + "\n" +
            "proc\nopt_expr\nopt_clean\ncheck -assert -noinit\n" +
            "memory -nomap\nopt_clean\ncheck -assert -noinit\n" +
            "select -assert-none t:$dlatch t:$adlatch t:$div t:$mod\n" +
            "stat\n" +
            f"write_json {experiment.relative}/netlist.json\n")
        experiment.run("synthesis", ["yosys", "-Q", "-T", "-s", str(script.relative_to(ROOT))],
                       2400)
        netlist = json.loads((experiment.out / "netlist.json").read_text())
        modules = netlist["modules"]
        names = {module.get("attributes", {}).get("hdlname", name).split()[0].lstrip("\\")
                 for name, module in modules.items()}
        required = ({"anvil_en1_top", "anvil_en1_kv_shared_cache",
                     "anvil_en1_owner_replay", "anvil_en1_asym_attn_ple",
                     "anvil_en1_csr_perf", "anvil_en1_fp32"}
                    if args.top == "anvil_en1_top" else {args.top})
        if not required <= names:
            raise RuntimeError("synthesis lost required connected hierarchy: " +
                               ", ".join(sorted(required - names)))
        cells = [cell for module in modules.values()
                 for cell in module.get("cells", {}).values()]
        forbidden = [cell["type"] for cell in cells
                     if cell["type"] in ("$dlatch", "$adlatch", "$div", "$mod")]
        if forbidden:
            raise RuntimeError("forbidden post-process cells: " + repr(forbidden))
        sequential = sum(cell["type"] in ("$dff", "$adff", "$dffe", "$adffe") for cell in cells)
        arithmetic = sum(cell["type"] in ("$mul", "$add", "$sub") for cell in cells)
        if sequential == 0 or arithmetic == 0:
            raise RuntimeError("synthesis lacks substantive sequential/arithmetic cells")
        memories = [cell for cell in cells if cell["type"].startswith("$mem")]
        if args.top in ("anvil_en1_top", "anvil_en1_kv_shared_cache") and not memories:
            raise RuntimeError("connected cache hierarchy lost all memory cells")
        experiment.receipt["structural_results"] = {
            "modules": len(modules), "sequential_cells": sequential,
            "arithmetic_cells": arithmetic, "memory_cells": len(memories),
            "forbidden_cells": len(forbidden), "required_hierarchy": sorted(required),
        }
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return experiment.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
