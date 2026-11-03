"""Real bounded replay with nonzero two-token causal dependencies, public pins only."""

import argparse
import re
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs
from text_cases import digest
from text_fixture import make_text_image
from text_reference import logits


def compare(output, expected, global_required):
    words = []
    for line in output.splitlines():
        if line.startswith("HIDDEN "):
            _, index, word = line.split()
            if int(index) != len(words) or not 0 <= int(word) <= 65535:
                raise RuntimeError("replay hidden output order/encoding")
            words.append(int(word))
    summaries = re.findall(r"^SUMMARY history ([^\n]+)$", output, re.MULTILINE)
    if len(words) != 8 or len(summaries) != 1:
        raise RuntimeError("incomplete replay-history comparison boundary")
    counts = dict((name, int(value)) for name, value in
                  (field.split("=") for field in summaries[0].split()))
    if (counts["components"] != 8 or counts["depth"] < 2 or counts["depth"] > 64 or
            counts["requests"] != counts["responses"] or counts["kv_bytes"] != 0 or
            counts["shadow"] > 1048576 or counts["live"] > 1048576 or
            any(counts[key] <= 0 for key in ("history", "input0", "input1", "weight_bytes",
                                           "metadata", "grants", "reprojections", "stalls",
                                           "local")) or global_required and not counts["global"]):
        raise RuntimeError("replay-history public coverage/conservation")
    if words != expected:
        raise RuntimeError(f"replay hidden BF16 mismatch expected={expected} observed={words}")
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/replay-history")
    parser.add_argument("--repair-of")
    parser.add_argument("--models", default="1,2")
    parser.add_argument("--precisions", default="0,1")
    parser.add_argument("--local-only", action="store_true")
    parser.add_argument("--max-cycles", type=int, default=2000000000)
    args = parser.parse_args()
    from text_cases import selected_values
    models = selected_values(parser, args.models, (1, 2), "--models")
    precisions = selected_values(parser, args.precisions, (0, 1), "--precisions")
    if args.max_cycles <= 0:
        parser.error("--max-cycles must be positive")
    exp = Experiment(args.out, "verifier-replay-history", source_inputs(), args.repair_of)
    error = None
    try:
        for tool, option in (("python3", "--version"), ("verilator", "--version"),
                             ("g++", "--version"), ("make", "--version")):
            exp.run(tool + "-version", [tool, option], 30)
        images = exp.out / "checkpoint-images"
        images.mkdir()
        cases = []
        import json
        for model in models:
            for precision in precisions:
                seed = (17, 43, 89)[(model - 1 + precision) % 3]
                image, tensors = make_text_image(model, precision, seed)
                path = images / f"m{model}-p{precision}-s{seed}.bin"
                path.write_bytes(image)
                for layer in ((2,) if args.local_only else (2, 5 if model == 1 else 6)):
                    reference = logits(tensors, model, seed, 2, stop_layer=layer)
                    expected = reference["layer_states_bf16"][layer][1]
                    name = f"m{model}-p{precision}-s{seed}-eval{layer}-t1"
                    expected_path = exp.out / (name + "-expected.json")
                    expected_path.write_text(json.dumps(reference) + "\n")
                    cases.append((name, model, precision, seed, layer, path, expected))
        exp.receipt.update(
            fixtures={str(path.relative_to(exp.out)): digest(path)
                      for path in (*images.iterdir(), *exp.out.glob("*-expected.json"))},
            expected_computed_before_observation=True,
            observations=[],
            scope="Two-token public replay start/output/done; all original tokens and weights "
                  "are immutable inputs, never host-produced hidden/KV answers. Metadata "
                  "responder supplies independently derived owner identities, not KV values. "
                  "Exact BF16 vector comparison; no top, cache-resident, modality or complete "
                  "allocation-ledger claim.")
        exp.save()
        obj = exp.relative / "compile-obj"
        sources = [str(path.relative_to(ROOT)) for path in source_inputs()
                   if path.suffix == ".sv" and path.parent == ROOT / "rtl"]
        exp.run("compile", [
            "verilator", "--cc", "--exe", "--build", "-O3", "-Wno-fatal",
            "--top-module", "anvil_en1_replay_execute", "-GCOMPACT=1",
            "--Mdir", str(obj), "-j", "2", "-CFLAGS", "-O3",
            "tests/simulation_schedule.vlt", *sources,
            str(ROOT / "tests/replay_history.cpp")], 1800)
        for name, model, precision, seed, layer, image, expected in cases:
            output = exp.run(name, [str(obj / "Vanvil_en1_replay_execute"),
                str(image.relative_to(ROOT)), str(model), str(precision), str(seed),
                str(layer), str(args.max_cycles)], 2400)
            counts = compare(output, expected, layer != 2)
            exp.receipt["observations"].append({
                "kind": "eval-2-1-history" if layer == 2 else "eval-global-history",
                "model": model, "precision": precision, "seed": seed,
                "attention": "local" if layer == 2 else "global",
                "layer": layer, "token": 1, "tokens": 2,
                "comparisons": 8, "completed": True, "mismatches": 0,
                "public_counts": counts,
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
