"""One compiled compact top per capacity/path, reused across runtime fixture cases.

This runner does not establish a feasible full-suite budget merely by existing.
Completed cases emit numerical observations; incomplete cases remain failures.
Decode, native modality and integrated liveness coverage are not supplied here.
"""

import argparse
import hashlib
import json
import math
import re
import shutil
import sys
import time

sys.dont_write_bytecode = True
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from numerical_reference import decode
from simulation_config import COMPACT_PARENT
from coverage_matrix import batch_cells
from text_cases import digest, load_cases, prepare_cases, selected_values
from verify import parse_result, require_child_sources
import itertools


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/top-batch")
    parser.add_argument("--repair-of")
    parser.add_argument("--fixture-set",
                        help="source-bound freshly generated independent text-cases manifest")
    parser.add_argument("--models", default="1,2")
    parser.add_argument("--precisions", default="0,1")
    parser.add_argument("--seeds", default="17,43,89")
    parser.add_argument("--contexts", default="1,16,17")
    parser.add_argument("--selection", choices=("cartesian", "representative"),
                        default="cartesian")
    parser.add_argument("--capacity", type=int, choices=(1, 3, 64), default=3)
    parser.add_argument("--fallback", action="store_true")
    parser.add_argument("--compiler-optimization", choices=("0", "1", "2", "3"), default="3",
                        help="Verilator optimization level; C++ remains -O3")
    parser.add_argument("--text-specialization", action="store_true",
                        help="structural wrapper ties only unused text-job inputs to zero")
    parser.add_argument("--compact-code", action="store_true",
                        help="retain shared C++ module bodies instead of aggressive inlining")
    parser.add_argument("--preserve-processes", action="store_true",
                        help="disable Verilator procedural splitting for FSM scheduling")
    parser.add_argument("--profile-cycles", type=int, default=0,
                        help="optional bounded incomplete run before full numerical execution")
    parser.add_argument("--pgo", action="store_true",
                        help="train GCC branch placement on the bounded run and rebuild")
    parser.add_argument("--build-jobs", type=int, choices=(1, 2, 4, 8), default=2)
    parser.add_argument("--with-baseline", action="store_true",
                        help="execute a matched bus baseline using the same fresh references")
    parser.add_argument("--max-cycles", type=int, default=2000000000)
    args = parser.parse_args()
    models = selected_values(parser, args.models, (1, 2), "--models")
    precisions = selected_values(parser, args.precisions, (0, 1), "--precisions")
    seeds = selected_values(parser, args.seeds, (17, 43, 89), "--seeds")
    contexts = selected_values(parser, args.contexts, (1, 16, 17), "--contexts")
    if args.max_cycles <= 0:
        parser.error("--max-cycles must be positive")
    if args.profile_cycles < 0 or args.pgo and args.profile_cycles <= 0:
        parser.error("--pgo requires a positive --profile-cycles")
    exp = Experiment(args.out, "verifier-top-batched-numerical", source_inputs(), args.repair_of)
    began = time.monotonic()
    error = None
    try:
        for tool, option in (("python3", "--version"), ("verilator", "--version"),
                             ("g++", "--version"), ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        cases = []
        fixture_hashes = {}
        keys = (tuple(cell.fixture_key for cell in batch_cells(
                    args.capacity, args.fallback, models, precisions, seeds, contexts))
                if args.selection == "representative" else
                tuple(itertools.product(models, precisions, seeds, contexts)))
        if not keys:
            raise ValueError("selected batch has no numerical comparison cells")
        manifest_path = (ROOT / args.fixture_set if args.fixture_set else prepare_cases(exp, keys))
        for case in load_cases(manifest_path, keys):
            fixture_hashes[case["image"]] = case["image_sha256"]
            fixture_hashes[case["expected"]] = case["expected_sha256"]
            cases.append((case["name"], case["model"], case["precision"], case["seed"],
                          case["tokens"], ROOT / case["image"], case["reference"]))
        exp.receipt.update(
            independent_fixture_manifest={"path": str(manifest_path.relative_to(ROOT)),
                                          "sha256": digest(manifest_path)},
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
        baseline = {}
        if args.with_baseline:
            output = exp.run("matched-baseline", [
                sys.executable, "-B", "tests/run_baseline.py",
                "--fixture-set", str(manifest_path.relative_to(ROOT)),
                "--models", args.models, "--precisions", args.precisions,
                "--seeds", args.seeds, "--contexts", args.contexts,
                "--selection", args.selection,
                *(("--batch-capacity", str(args.capacity),
                   "--batch-fallback", str(int(args.fallback)))
                  if args.selection == "representative" else ()),
                "--out", str(exp.relative / "baseline")], 2700)
            path, receipt = parse_result(output, ROOT)
            if exp.relative not in path.parents:
                raise RuntimeError("baseline receipt is outside this fresh run")
            require_child_sources(receipt, exp.receipt["source_sha256"])
            if receipt["independent_fixture_manifest"] != exp.receipt["independent_fixture_manifest"]:
                raise RuntimeError("baseline and candidate did not bind the same fixture manifest")
            exp.receipt["children"] = [{
                "name": "matched-baseline", "receipt": str(path),
                "sha256": digest(ROOT / path)}]
            for record in receipt["observations"]:
                key = tuple(record[field] for field in ("model", "precision", "seed", "tokens"))
                if key in baseline or record["accepted_external_kv_bytes"] <= 0:
                    raise RuntimeError("baseline denominator is duplicated or empty")
                baseline[key] = record["accepted_external_kv_bytes"]
            exp.save()
        obj = exp.relative / "compile-obj"
        sources = [str(path.relative_to(ROOT)) for path in source_inputs()
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        top = "anvil_en1_top"
        wrapper_args = []
        if args.text_specialization:
            declaration = (ROOT / "rtl/anvil_en1_top.sv").read_text()
            ports = declaration.split(") (", 1)[1].split(");", 1)[0]
            zero_inputs = ("job_mode", "job_patch_rows", "job_patch_cols",
                           "job_audio_frames", "vision_weights_base", "audio_weights_base",
                           "image_base", "audio_base")
            wrapper = exp.out / "text_top.sv"
            wrapper.write_text(
                "module text_top (" + ports + ");\n"
                "anvil_en1_top #(" +
                ", ".join(f".{name}({value})" for name, value in parameters.items()) +
                ") product (" +
                ", ".join(f".{name}('0)" for name in zero_inputs) +
                ", .*);\nendmodule\n")
            exp.receipt["structural_wrapper_sha256"] = hashlib.sha256(
                wrapper.read_bytes()).hexdigest()
            exp.receipt["constant_public_inputs"] = dict.fromkeys(zero_inputs, 0)
            exp.save()
            top = "text_top"
            wrapper_args = ["--prefix", "Vanvil_en1_top", str(wrapper.relative_to(ROOT))]
        exp.run("compile", [
            "verilator", "--cc", "--exe", "--build",
            "-O" + args.compiler_optimization, "-Wno-fatal",
            *(["--inline-mult", "0", "--expand-limit", "32",
               "--output-split-cfuncs", "5000"] if args.compact_code else []),
            *(["-fno-split"] if args.preserve_processes else []),
            "--top-module", top, "--Mdir", str(obj),
            "-j", str(args.build_jobs),
            "-CFLAGS", "-O3" + (" -fprofile-generate" if args.pgo else ""),
            *(["-LDFLAGS", "-fprofile-generate"] if args.pgo else []),
            *(wrapper_args if args.text_specialization else
              [f"-G{name}={value}" for name, value in parameters.items()]),
            "tests/simulation_schedule.vlt", *sources,
            str(ROOT / "tests/top_smoke.cpp")], 1800)
        if args.profile_cycles:
            name, model, precision, seed, tokens, image_path, _ = cases[0]
            output = exp.run("bounded-profile", [
                str(obj / "Vanvil_en1_top"), str(image_path.relative_to(ROOT)),
                str(model), str(precision), str(seed), str(args.profile_cycles),
                str(tokens)], 2400, (1,))
            stderr = (exp.out / "bounded-profile.stderr.txt").read_text()
            if (f"INCOMPLETE cycle_limit={args.profile_cycles} " not in output or
                    "FAIL cycle limit reached without complete top result" not in stderr):
                raise RuntimeError("profile failed before the intended incomplete boundary")
            exp.receipt["incomplete_profile"] = next(
                line for line in output.splitlines() if line.startswith("PERFORMANCE "))
            exp.save()
            if args.pgo:
                profiles = list((ROOT / obj).glob("*.gcda"))
                if not profiles:
                    raise RuntimeError("GCC profile training retained no counters")
                exp.receipt["compiler_profiles"] = {
                    str(path.relative_to(exp.out)): digest(path) for path in profiles}
                for path in (ROOT / obj).iterdir():
                    if path.suffix in (".o", ".a", ".gch"):
                        path.unlink()
                exp.run("profile-guided-rebuild", [
                    "make", "-C", str(obj), "-f", "Vanvil_en1_top.mk",
                    "-j", str(args.build_jobs),
                    "VM_USER_CFLAGS=-O3 -fprofile-use",
                    "VM_USER_LDFLAGS=-fprofile-use", "Vanvil_en1_top"], 1800)
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
            if args.with_baseline:
                denominator = baseline[model, precision, seed, tokens]
                if 100 * counts["kv_bytes"] >= 45 * denominator:
                    raise RuntimeError("candidate external KV traffic exceeds the strict bound")
                exp.receipt["observations"].append({
                    "kind": "candidate-public-kv-traffic",
                    "model": model, "precision": precision, "seed": seed,
                    "capacity": args.capacity, "tokens": tokens,
                    "fallback": int(args.fallback),
                    "accepted_external_kv_bytes": counts["kv_bytes"],
                    "matched_unshared_external_kv_bytes": denominator,
                    "comparisons": counts["reads"], "completed": True, "mismatches": 0,
                })
            exp.save()
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    finally:
        obj = exp.out / "compile-obj"
        if obj.exists():
            shutil.rmtree(obj)
    exp.receipt["complete_elapsed_seconds"] = time.monotonic() - began
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
