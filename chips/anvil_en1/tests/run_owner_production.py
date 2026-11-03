"""Pairwise production-width owner tiles; no full-width long neural inference claim."""

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from owner_fixture import check_skip, production_owner_image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/owner-production")
    parser.add_argument("--repair-of")
    parser.add_argument("--compact", action="store_true",
                        help="eight pairwise tiles; full production arithmetic/directory widths")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-production-owner-tiles", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        check_skip()
        images = exp.out / "checkpoint-images"
        images.mkdir()
        cases = []
        expected_records = []
        # Cross both precisions and selectors with both anchor types. Positions
        # and seeds are pairwise here; the separate compact tile matrix is dense.
        for model in (1, 2):
            for precision in (0, 1):
                for global_ in (0, 1):
                    for selector in (0, 1):
                        if args.compact and selector != ((model - 1) ^ precision ^ global_):
                            continue
                        index = len(cases)
                        owner = ((13, 14) if model == 1 else (22, 23))[global_]
                        seed = (17, 43, 89)[index % 3]
                        context = (1, 16, 17, 511, 512, 513, 1025)[index % 7]
                        dimension = 512 if global_ else 256
                        head = model - 1
                        component = dimension - 2
                        name = f"m{model}-p{precision}-s{seed}-o{owner}-t{context-1}-v{selector}"
                        image, source, expected = production_owner_image(
                            model, precision, seed, owner, context - 1, selector,
                            head, component)
                        image_path = images / (name + ".sparse")
                        source_path = images / (name + "-source.bin")
                        image_path.write_bytes(image)
                        source_path.write_bytes(source)
                        pair = expected[component] | expected[component + 1] << 16
                        cases.append([name, model, precision, owner, context - 1, selector,
                                      head, component, pair, 0, dimension, 0,
                                      str(image_path.relative_to(ROOT)),
                                      str(source_path.relative_to(ROOT))])
                        expected_records.append({
                            "name": name, "hidden": len(source) // 2, "dimension": dimension,
                            "head": head, "component": component, "expected_pair": pair,
                            "normalized_rotated_bf16": expected,
                        })
                        print(f"PROGRESS production owner fixture={name}", flush=True)
        manifest = exp.out / "cases.txt"
        manifest.write_text("".join(" ".join(map(str, row)) + "\n" for row in cases))
        expected_path = exp.out / "expected.json"
        expected_path.write_text(json.dumps(expected_records) + "\n")
        exp.receipt["fixtures"] = {
            str(path.relative_to(exp.out)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (manifest, expected_path, *sorted(images.iterdir()))}
        exp.receipt["expected_computed_before_observation"] = True
        exp.receipt["scope"] = (
            f"{len(cases)} production-width nonzero owner K/V projection, input/head RMS and RoPE "
            "pairs with real payload reads, including E4B head 1 and final components. "
            "All nonselected tensor RNG states are advanced in ABI order. Sparse original "
            "weight fixtures reject every missing payload read; no hidden/KV answer enters "
            "the DUT. Position/seed coverage is pairwise, not the full required C matrix.")
        exp.save()
        obj = exp.relative / "compile-obj"
        sources = [str(path.relative_to(ROOT)) for path in source_inputs()
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        exp.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-O3", "-Wno-fatal",
            "--top-module", "anvil_en1_owner_kv_tile", "--Mdir", str(obj),
            "-CFLAGS", "-O3", "-j", "2", *sources,
            str(ROOT / "tests/owner_tile.cpp")], 1800)
        output = exp.run("simulation", [str(obj / "Vanvil_en1_owner_kv_tile"),
                                       str(manifest.relative_to(ROOT))], 2400)
        if f"SUMMARY owner_tile comparisons={len(cases)} rejected=0 " not in output:
            raise RuntimeError("incomplete production owner tile comparisons")
        exp.receipt["numerical_pair_comparisons"] = len(cases)
        exp.receipt["summary"] = output.strip()
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
