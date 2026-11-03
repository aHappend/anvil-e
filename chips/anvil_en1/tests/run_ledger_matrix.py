"""Independent public-pin allocation sums, phase changes and reset conservation."""

import argparse
import hashlib
import re
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/ledger-matrix")
    parser.add_argument("--repair-of")
    parser.add_argument("--defect", choices=("missing-live-frame-allocation",))
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-ledger-matrix", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        source = Path("rtl/anvil_en1_allocation_ledger.sv")
        if args.defect:
            original = (ROOT / source).read_text()
            before = ("assign equivalent_terms[64*term+:64] = "
                      "component_live_bytes[64*term+:64];")
            after = ("assign equivalent_terms[64*term+:64] = term == 5 ? "
                     "64'd0 : component_live_bytes[64*term+:64];")
            if original.count(before) != 1:
                raise RuntimeError("allocation mutation site is not unique")
            source = exp.relative / "mutant-source" / source.name
            (ROOT / source).parent.mkdir()
            (ROOT / source).write_text(original.replace(before, after))
            exp.receipt["mutation"] = {
                "name": args.defect, "source": str(source),
                "sha256": hashlib.sha256((ROOT / source).read_bytes()).hexdigest(),
                "required_rejection": "LEDGER_MATRIX_SUM",
            }
        exp.receipt["coverage"] = []
        for breakdown in (0, 1):
            obj = exp.relative / f"compile-obj-{breakdown}"
            try:
                exp.run(f"compile-{breakdown}", [
                    "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                    "--top-module", "anvil_en1_allocation_ledger", "--Mdir", str(obj),
                    f"-GREPORT_BREAKDOWN={breakdown}", "-CFLAGS",
                    f"-DLEDGER_BREAKDOWN={breakdown}", "-j", "2",
                    str(source),
                    str(ROOT / "tests/ledger_matrix.cpp")], 1800)
                output = exp.run(
                    f"simulation-{breakdown}",
                    [str(obj / "Vanvil_en1_allocation_ledger")], 2400,
                    expected_exit_codes=(1,) if args.defect else (0,))
                if args.defect:
                    stderr = (exp.out / f"simulation-{breakdown}.stderr.txt").read_text()
                    if "FAIL LEDGER_MATRIX_SUM" not in stderr:
                        raise RuntimeError("mutation did not fail its allocation comparison")
                    exp.receipt["coverage"].append({
                        "breakdown": breakdown,
                        "mutation_rejected": args.defect,
                        "assertion": "LEDGER_MATRIX_SUM",
                    })
                    exp.save()
                    continue
                marker = re.search(r"SUMMARY ledger_matrix ([^\n]+)", output)
                if not marker:
                    raise RuntimeError("missing public-ledger matrix completion")
                fields = dict(item.split("=") for item in marker.group(1).split())
                counts = {name: int(value) for name, value in fields.items()
                          if name != "seeds"}
                if (counts["breakdown"] != breakdown or counts["compared"] < 500 or
                        counts["accepted"] != counts["compared"] + counts["canceled"] or
                        any(counts[key] <= 0 for key in
                            ("canceled", "ordinary", "fallback", "errors", "overlaps")) or
                        counts["reset_checks"] < 9 or fields["seeds"] != "17,43,89"):
                    raise RuntimeError("incomplete public-ledger matrix coverage")
                exp.receipt["coverage"].append(counts)
                exp.save()
            finally:
                if (ROOT / obj).exists():
                    shutil.rmtree(ROOT / obj)
        exp.receipt["scope"] = (
            "Public allocation arithmetic and six-edge observation alignment; "
            "not integrated allocation completeness, fallback execution or traffic savings.")
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
