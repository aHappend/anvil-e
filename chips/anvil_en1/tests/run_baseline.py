"""Independently materialized compact owner-copy baseline with real bus handshakes."""

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from coverage_matrix import batch_cells, fixture_keys
from text_cases import digest, load_cases, prepare_cases, selected_values
import itertools


def compare_traffic(output, cases, metadata):
    if not cases:
        raise RuntimeError("baseline requires nonempty public-handshake comparisons")
    observed = {}
    summaries = []
    for line in output.splitlines():
        if line.startswith("CASE "):
            _, name, *fields = line.split()
            if name in observed:
                raise RuntimeError("duplicate baseline completion: " + name)
            observed[name] = {key: int(value) for key, value in
                              (field.split("=") for field in fields)}
        elif line.startswith("SUMMARY baseline "):
            summaries.append({key: int(value) for key, value in
                              (field.split("=") for field in line.split()[2:])})
    if set(observed) != {case[0] for case in cases} or len(summaries) != 1:
        raise RuntimeError("incomplete actual-handshake baseline")
    observations = []
    for name, model, tokens, writes, reads, _ in cases:
        counts = observed[name]
        if (counts["write_bytes"] != writes or counts["read_bytes"] != reads or
                writes <= 0 or reads <= 0 or counts["sources"] <= 0 or
                counts["responses"] * 4 != writes + reads):
            raise RuntimeError("baseline public-transaction conservation: " + name)
        case = metadata[name]
        observations.append({
            "kind": "matched-unshared-public-traffic",
            "model": model, "precision": case["precision"], "seed": case["seed"],
            "tokens": tokens, "external_kv_write_bytes": counts["write_bytes"],
            "external_kv_read_bytes": counts["read_bytes"],
            "accepted_external_kv_bytes": counts["write_bytes"] + counts["read_bytes"],
            "responses": counts["responses"], "comparisons": counts["sources"],
            "completed": True, "mismatches": 0,
        })
    summary = summaries[0]
    if (summary["cases"] != len(cases) or
            summary["write_bytes"] != sum(row["write_bytes"] for row in observed.values()) or
            summary["read_bytes"] != sum(row["read_bytes"] for row in observed.values()) or
            summary["responses"] != sum(row["responses"] for row in observed.values()) or
            summary["owner_pairs"] != sum(row["sources"] for row in observed.values())):
        raise RuntimeError("baseline aggregate conservation")
    return observations


def schedule(model, tokens, expected):
    layers, owners, local_anchor, global_anchor, period = (
        (35, 15, 13, 14, 5) if model == 1 else (42, 24, 22, 23, 6))
    padded = (tokens + 15) // 16 * 16
    for reading in (False, True):
        for layer in range(layers):
            global_ = (layer + 1) % period == 0
            owner = layer if layer < owners else global_anchor if global_ else local_anchor
            dimension = 8 if global_ else 4
            first = 0 if global_ else max(0, tokens - 4)
            end = tokens if reading else padded if global_ else first + 4
            for token in range(first, end):
                for selector in (0, 1):
                    for component in range(0, dimension, 2):
                        if token < tokens:
                            vector = expected["owner_kv_bf16"][str(owner)][selector][token]
                            data = vector[component] | vector[component + 1] << 16
                        else:
                            data = 0
                        address = (0x100000000 + (layer << 20) + (selector << 19) +
                                   (token << 4) + (component // 2 << 2))
                        yield [int(not reading), address, data, owner, token, selector,
                               component, int(not reading and token < tokens)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/kv-baseline")
    parser.add_argument("--repair-of")
    parser.add_argument("--fixture-set",
                        help="source-bound freshly generated independent text-cases manifest")
    parser.add_argument("--seeds", default="17,43,89")
    parser.add_argument("--models", default="1,2")
    parser.add_argument("--precisions", default="0,1")
    parser.add_argument("--contexts", default="1,16,17")
    parser.add_argument("--selection", choices=("cartesian", "representative"),
                        default="cartesian")
    parser.add_argument("--batch-capacity", type=int, choices=(1, 3, 64))
    parser.add_argument("--batch-fallback", type=int, choices=(0, 1))
    args = parser.parse_args()
    if ((args.batch_capacity is None) != (args.batch_fallback is None) or
            args.batch_capacity is not None and args.selection != "representative"):
        parser.error("batch selection requires representative mode, capacity and fallback")
    models = selected_values(parser, args.models, (1, 2), "--models")
    precisions = selected_values(parser, args.precisions, (0, 1), "--precisions")
    seeds = selected_values(parser, args.seeds, (17, 43, 89), "--seeds")
    contexts = selected_values(parser, args.contexts, (1, 16, 17), "--contexts")
    exp = Experiment(args.out, "verifier-handshake-kv-baseline", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("verilator", "--version"), ("g++", "--version"),
                             ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        cases = []
        metadata = {}
        fixture_hashes = {}
        keys = (tuple(key for key in fixture_keys() if key[0] in models and
                      key[1] in precisions and key[2] in seeds and key[3] in contexts)
                if args.selection == "representative" else
                tuple(itertools.product(models, precisions, seeds, contexts)))
        if args.batch_capacity is not None:
            keys = tuple(cell.fixture_key for cell in batch_cells(
                args.batch_capacity, args.batch_fallback, models, precisions, seeds, contexts))
        manifest_path = (ROOT / args.fixture_set if args.fixture_set else prepare_cases(exp, keys))
        for case in load_cases(manifest_path, keys):
            name, model, tokens = case["name"], case["model"], case["tokens"]
            metadata[name] = case
            rows = list(schedule(model, tokens, case["reference"]))
            path = exp.out / (name + "-commands.txt")
            path.write_text("".join(" ".join(map(str, row)) + "\n" for row in rows))
            fixture_hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
            padded = (tokens + 15) // 16 * 16
            local_layers = 28 if model == 1 else 35
            write_bytes = 4 * (local_layers * 4 * 4 + 7 * 8 * padded)
            read_bytes = 4 * (local_layers * 4 * min(tokens, 4) + 7 * 8 * tokens)
            if (sum(4 for row in rows if row[0]) != write_bytes or
                    sum(4 for row in rows if not row[0]) != read_bytes):
                raise RuntimeError("baseline schedule disagrees with geometry sums")
            cases.append([name, model, tokens, write_bytes, read_bytes,
                          str(path.relative_to(ROOT))])
            print(f"PROGRESS baseline reference={name} commands={len(rows)}", flush=True)
        manifest = exp.out / "cases.txt"
        manifest.write_text("".join(" ".join(map(str, row)) + "\n" for row in cases))
        fixture_hashes[manifest.name] = hashlib.sha256(manifest.read_bytes()).hexdigest()
        exp.receipt["fixtures"] = fixture_hashes
        exp.receipt["independent_fixture_manifest"] = {
            "path": str(manifest_path.relative_to(ROOT)), "sha256": digest(manifest_path)}
        exp.receipt["expected_computed_before_observation"] = True
        exp.receipt["seeds"] = seeds
        exp.receipt["scope"] = (
            "Compact real model owner-K/V copies, occupied padding and last-token attention "
            "reads. Every command receives a successful response; not a candidate traffic "
            "savings claim or production-width inference.")
        exp.save()
        obj = exp.relative / "compile-obj"
        exp.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-Wno-fatal",
            "--top-module", "kv_baseline", "--Mdir", str(obj),
            "-j", "2", "tests/kv_baseline.sv", str(ROOT / "tests/kv_baseline.cpp")], 1800)
        output = exp.run("simulation", [str(obj / "Vkv_baseline"),
                                       str(manifest.relative_to(ROOT))], 2400)
        exp.receipt["observations"] = compare_traffic(output, cases, metadata)
        exp.receipt["cases"] = [
            {"name": name, "model": model, "tokens": tokens,
             "expected_write_bytes": writes, "expected_read_bytes": reads}
            for name, model, tokens, writes, reads, _ in cases]
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
