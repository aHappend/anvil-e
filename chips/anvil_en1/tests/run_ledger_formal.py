"""Bounded public-port ledger sum proof for a retained simulator disagreement."""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/ledger-sum-proof")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-ledger-sum-proof", source_inputs(), args.repair_of)
    error = None
    try:
        exp.run("yosys-version", ["yosys", "-V"], 30)
        settings = {
            "component_live_bytes": 512 << (64 * 22),
            "component_shadow_bytes": 512 << (64 * 22),
            "metadata_bytes": 0, "shadow_metadata_bytes": 0,
            "integration_bytes": 32, "native_workspace_bytes": 0,
            "native_workspace_shadow_bytes": 0, "native_controller_bytes": 128,
            "observation_valid": 0, "observation_model": 1,
            "observation_check_valid": 0, "observation_fallback": 0,
        }
        expected = {
            "equivalent_bytes": 544, "equivalent_shadow_bytes": 544,
            "native_scratch_bytes": 128, "native_scratch_shadow_bytes": 128,
            "text_workspace_bytes": 416, "text_workspace_shadow_bytes": 416,
            "report_partition_error": 0,
        }
        exp.receipt["public_inputs"] = settings
        exp.receipt["expected_outputs"] = expected
        exp.receipt["scope"] = (
            "12-edge bounded sum proof after two reset edges; constant public "
            "inputs, no report-valid or integrated allocation coverage")
        exp.save()
        script = exp.out / "proof.ys"
        script.write_text(
            "read_verilog -sv rtl/anvil_en1_allocation_ledger.sv\n"
            "hierarchy -check -top anvil_en1_allocation_ledger\n"
            "proc\nopt_expr\nopt_clean\ncheck -assert\n"
            "flatten\nasync2sync\ndffunmap\nopt_clean\n"
            "sat -verify -seq 12 -set-def-inputs -set rst_n 1 "
            "-set-at 1 rst_n 0 -set-at 2 rst_n 0 " +
            " ".join(f"-set {name} {value}" for name, value in settings.items()) +
            " -prove-skip 8 " +
            " ".join(f"-prove {name} {value}" for name, value in expected.items()) +
            "\n")
        output = exp.run("proof", ["yosys", "-Q", "-T", "-s",
                                  str(script.relative_to(ROOT))], 2400)
        if "SAT proof finished - no model found: SUCCESS!" not in output:
            raise RuntimeError("public ledger sum proof did not complete successfully")
        exp.receipt["proved_outputs"] = list(expected)
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
