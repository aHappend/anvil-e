"""One compiled compact top per capacity/path, reused across runtime fixture cases.

This runner does not establish a feasible full-suite budget merely by existing.
Completed cases emit numerical observations; incomplete cases remain failures.
Decode, native modality and integrated liveness coverage are not supplied here.
"""

import argparse
import hashlib
import itertools
import json
import math
import re
import shutil
import sys

sys.dont_write_bytecode = True
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from numerical_reference import decode
from simulation_config import COMPACT_PARENT
from text_fixture import make_text_image
from text_reference import logits


def compare(output, expected, tokens):
    if len(expected["logits"]) != 32 or not all(
            math.isfinite(value) for value in expected["logits"]):
        raise ValueError("independent reference requires 32 finite logits")
    observed = []
    for line in output.splitlines():
        if not line.startswith("LOGIT "):
            continue
        _, index, value = line.split()
        if int(index) != len(observed):
            raise RuntimeError("out-of-order observed logit")
        _, category, number = decode(int(value), 8, 7)
        if category != "finite":
            raise RuntimeError("nonfinite fixture output")
        observed.append(float(number))
    summaries = re.findall(r"^SUMMARY top ([^\n]+)$", output, re.MULTILINE)
    if len(observed) != 32 or len(summaries) != 1:
        raise RuntimeError("incomplete top numerical comparison boundary")
    counts = dict((name, int(value)) for name, value in
                  (field.split("=") for field in summaries[0].split()))
    if (counts["logits"] != 32 or counts["tokens"] != tokens or
            counts["reads"] <= 0 or counts["weight_bytes"] <= 0 or
            counts["input_bytes"] <= 0 or counts["kv_bytes"] != 0 or
            4 * counts["reads"] != counts["weight_bytes"] + counts["input_bytes"]):
        raise RuntimeError("incomplete top public-transaction conservation")
    errors = [abs(actual - reference)
              for actual, reference in zip(observed, expected["logits"])]
    for index, (actual, error, reference) in enumerate(
            zip(observed, errors, expected["logits"])):
        if not -30 <= actual <= 30 or error > 0.25 + 0.02 * abs(reference):
            raise RuntimeError(
                f"logit mismatch index={index} observed={actual} reference={reference}")
    return counts, max(errors)


def selected_values(parser, raw, legal, name):
    values = tuple(int(value) for value in raw.split(","))
    if not values or len(set(values)) != len(values) or any(v not in legal for v in values):
        parser.error(name + " must select distinct values from " + ",".join(map(str, legal)))
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/top-batch")
    parser.add_argument("--repair-of")
    parser.add_argument("--models", default="1,2")
    parser.add_argument("--precisions", default="0,1")
    parser.add_argument("--seeds", default="17,43,89")
    parser.add_argument("--contexts", default="1,16,17")
    parser.add_argument("--capacity", type=int, choices=(1, 3, 64), default=3)
    parser.add_argument("--fallback", action="store_true")
    parser.add_argument("--compiler-optimization", choices=("0", "1", "2", "3"), default="3",
                        help="Verilator optimization level; C++ remains -O3")
    parser.add_argument("--max-cycles", type=int, default=2000000000)
    args = parser.parse_args()
    models = selected_values(parser, args.models, (1, 2), "--models")
    precisions = selected_values(parser, args.precisions, (0, 1), "--precisions")
    seeds = selected_values(parser, args.seeds, (17, 43, 89), "--seeds")
    contexts = selected_values(parser, args.contexts, (1, 16, 17), "--contexts")
    if args.max_cycles <= 0:
        parser.error("--max-cycles must be positive")
    exp = Experiment(args.out, "verifier-top-batched-numerical", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("python3", "--version"), ("verilator", "--version"),
                             ("g++", "--version"), ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        images = exp.out / "checkpoint-images"
        images.mkdir()
        cases = []
        fixture_hashes = {}
        for model, precision, seed in itertools.product(models, precisions, seeds):
            image, tensors = make_text_image(model, precision, seed)
            stem = f"m{model}-p{precision}-s{seed}"
            image_path = images / (stem + ".bin")
            image_path.write_bytes(image)
            fixture_hashes[str(image_path.relative_to(exp.out))] = (
                hashlib.sha256(image).hexdigest())
            for tokens in contexts:
                name = stem + f"-n{tokens}"
                expected = logits(tensors, model, seed, tokens)
                expected_path = exp.out / (name + "-expected.json")
                expected_path.write_text(json.dumps(expected) + "\n")
                fixture_hashes[expected_path.name] = hashlib.sha256(
                    expected_path.read_bytes()).hexdigest()
                cases.append((name, model, precision, seed, tokens, image_path, expected))
                print("PROGRESS independent reference=" + name, flush=True)
        exp.receipt.update(
            fixtures=fixture_hashes, expected_computed_before_observation=True,
            requested_cases=[{"name": name, "model": model, "precision": precision,
                              "seed": seed, "tokens": tokens}
                             for name, model, precision, seed, tokens, _, _ in cases],
            observations=[],
            scope="Prefill numerical comparisons and accepted read classification only; "
                  "not decode, five-domain, integrated allocation or production-cache coverage.")
        parameters = dict(COMPACT=1, RESIDENT_ENTRIES=args.capacity,
                          FORCE_FALLBACK=int(args.fallback), **COMPACT_PARENT)
        exp.receipt["parameters"] = parameters
        exp.save()
        obj = exp.relative / "compile-obj"
        sources = [str(path.relative_to(ROOT)) for path in source_inputs()
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        exp.run("compile", [
            "verilator", "--cc", "--exe", "--build",
            "-O" + args.compiler_optimization, "-Wno-fatal",
            "--top-module", "anvil_en1_top", "--Mdir", str(obj),
            "-j", "2", "-CFLAGS", "-O3",
            *[f"-G{name}={value}" for name, value in parameters.items()],
            "tests/simulation_schedule.vlt", *sources,
            str(ROOT / "tests/top_smoke.cpp")], 1800)
        for name, model, precision, seed, tokens, image_path, expected in cases:
            output = exp.run(name, [
                str(obj / "Vanvil_en1_top"), str(image_path.relative_to(ROOT)),
                str(model), str(precision), str(seed), str(args.max_cycles), str(tokens)], 2400)
            counts, maximum_error = compare(output, expected, tokens)
            exp.receipt["observations"].append({
                "kind": "top-numerical", "model": model, "precision": precision,
                "seed": seed, "capacity": args.capacity, "tokens": tokens,
                "fallback": int(args.fallback), "comparisons": 32,
                "completed": True, "mismatches": 0, "public_counts": counts,
                "maximum_logit_absolute_error": maximum_error,
            })
            exp.save()
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
