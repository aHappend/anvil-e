"""Public owner-only K/V projection, learned/unscaled RMS and RoPE comparisons."""

import argparse
import hashlib
import json
import shutil
import struct
import sys
from fractions import Fraction
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from numerical_reference import encode
from run_rotary import rotation
from text_fixture import make_text_image
from text_reference import bf16, norm, project


def expected_vector(tensors, owner, token, seed, selector, global_attention):
    source = [bf16(Fraction(((13 * token + 5 * c + seed) & 31) - 16, 32))
              for c in range(8)]
    normalized = norm(source, tensors[0x100, owner][0])
    projected = project(tensors[0x105 if selector else 0x103, owner], normalized)
    normalized = norm(projected, None if selector else tensors[0x104, owner][0])
    bits = [encode(x, exponent_bits=8, fraction_bits=7) for x in normalized]
    if not selector:
        half = len(bits) // 2
        pairs = [rotation(int(global_attention), len(bits), i, token,
                          bits[i], bits[i + half]) for i in range(half)]
        bits = [word & 65535 for word in pairs] + [word >> 16 for word in pairs]
    return source, bits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/owner-tile")
    parser.add_argument("--repair-of")
    parser.add_argument("--defects", action="store_true")
    args = parser.parse_args()
    exp = Experiment(args.out, "verifier-owner-tile", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        images = exp.out / "checkpoint-images"
        images.mkdir()
        cases = []
        expected_records = []
        for model in (1, 2):
            local, global_ = (13, 14) if model == 1 else (22, 23)
            for precision in (0, 1):
                for seed in (17, 43, 89):
                    image, tensors = make_text_image(model, precision, seed)
                    stem = f"m{model}-p{precision}-s{seed}"
                    image_path = images / (stem + ".bin")
                    image_path.write_bytes(image)
                    for owner in (0, local, global_):
                        for context in (1, 16, 17, 511, 512, 513, 1025):
                            token = context - 1
                            source_path = images / (stem + f"-t{token}.bin")
                            for selector in (0, 1):
                                source, expected = expected_vector(
                                    tensors, owner, token, seed, selector, owner == global_)
                                source_path.write_bytes(b"".join(
                                    struct.pack("<H", encode(x, exponent_bits=8,
                                                            fraction_bits=7))
                                    for x in source))
                                for component in sorted({0, len(expected) - 2}):
                                    name = (f"{stem}-o{owner}-t{token}"
                                            f"-v{selector}-c{component}")
                                    pair = expected[component] | expected[component + 1] << 16
                                    cases.append([name, model, precision, owner, token,
                                                  selector, 0, component, pair, 0,
                                                  len(expected), 0,
                                                  str(image_path.relative_to(ROOT)),
                                                  str(source_path.relative_to(ROOT))])
                                    expected_records.append({
                                        "name": name, "normalized_rotated_bf16": expected,
                                        "expected_pair": pair})
                    valid = cases[-1]
                    for name, changes, code, fault in (
                            ("shared-owner", {3: global_ + 1}, 7, 0),
                            ("odd-component", {7: 1}, 5, 0),
                            ("past-head", {7: 8}, 5, 0),
                            ("past-token", {4: 131072}, 5, 0),
                            ("past-head-index", {6: 1}, 5, 0),
                            ("model-reject", {1: 3}, 6, 0),
                            ("precision-reject", {2: 2}, 6, 0),
                            ("weight-error", {}, 2, 1),
                            ("source-error", {}, 7, 2)):
                        row = list(valid)
                        row[0] = stem + "-" + name
                        for index, value in changes.items():
                            row[index] = value
                        row[8:10] = [0, code]
                        row[11] = fault
                        cases.append(row)
        manifest = exp.out / "cases.txt"
        manifest.write_text("".join(" ".join(map(str, row)) + "\n" for row in cases))
        (exp.out / "expected.json").write_text(json.dumps(expected_records) + "\n")
        exp.receipt["fixtures"] = {
            str(path.relative_to(exp.out)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (manifest, exp.out / "expected.json", *sorted(images.iterdir()))}
        exp.receipt["expected_computed_before_observation"] = True
        exp.receipt["configuration"] = {
            "compact": True, "models": [1, 2], "precisions": [0, 1],
            "seeds": [17, 43, 89], "contexts": [1, 16, 17, 511, 512, 513, 1025],
            "owner_types": ["first-local", "local-anchor", "global-anchor"],
            "selectors": ["K", "V"], "component_pairs": ["first", "last"],
            "scope": "Real compact owner tile arithmetic; not full top or production-width coverage"}
        exp.save()
        obj = exp.relative / "compile-obj"
        sources = [str(path.relative_to(ROOT)) for path in source_inputs()
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        variants = [("original", sources, None)]
        if args.defects:
            original = (ROOT / "rtl/anvil_en1_owner_kv_tile.sv").read_text()
            mutations = (
                ("shared-kv-computation",
                 "selected_layer_count : selected_owner_count)) begin",
                 "selected_layer_count : selected_layer_count)) begin",
                 "OWNER_REJECTED_BEFORE_ACCESS"),
                ("key-value-identity",
                 "(selector_hold ? 16'h0105 : 16'h0103)",
                 "(selector_hold ? 16'h0103 : 16'h0103)",
                 "OWNER_NUMERICAL_PAIR"),
                ("missing-value-normalization",
                 "if (selector_hold) begin\n"
                 "                                memory_owner <= MEMORY_SCALE;\n"
                 "                                state <= NORM_START;",
                 "if (selector_hold) begin\n"
                 "                                current_component <= component_hold;\n"
                 "                                second_component <= 0;\n"
                 "                                state <= PAIR_SETUP;",
                 "OWNER_NUMERICAL_PAIR"),
            )
            exp.receipt["mutations"] = []
            for name, before, after, assertion in mutations:
                if original.count(before) != 1:
                    raise RuntimeError("owner mutation site is not unique: " + name)
                path = exp.out / (name + ".sv")
                path.write_text(original.replace(before, after))
                exp.receipt["mutations"].append({
                    "name": name, "source": str(path.relative_to(ROOT)),
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "intended_assertion": assertion})
                variants.append((name, [
                    str(path.relative_to(ROOT)) if source == "rtl/anvil_en1_owner_kv_tile.sv"
                    else source for source in sources], assertion))
        exp.save()
        for name, variant_sources, assertion in variants:
            exp.run(name + "-compile", [
                "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                "--top-module", "anvil_en1_owner_kv_tile", "--Mdir", str(obj),
                "-GCOMPACT=1", "-j", "2", *variant_sources,
                str(ROOT / "tests/owner_tile.cpp")], 1800)
            output = exp.run(name + "-simulation", [
                str(obj / "Vanvil_en1_owner_kv_tile"), str(manifest.relative_to(ROOT))],
                2400, (1,) if assertion else (0,))
            if assertion:
                stderr = (exp.out / (name + "-simulation.stderr.txt")).read_text()
                if "FAIL " + assertion not in stderr:
                    raise RuntimeError("owner mutant missed its intended assertion: " + name)
            else:
                if f"SUMMARY owner_tile comparisons={len(cases)} rejected=108 " not in output:
                    raise RuntimeError("incomplete owner tile numerical/error comparisons")
                exp.receipt["summary"] = output.strip()
            shutil.rmtree(ROOT / obj)
        exp.receipt["comparison_cases"] = len(cases)
        exp.receipt["numerical_pair_comparisons"] = len(expected_records)
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
