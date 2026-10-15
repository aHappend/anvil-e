#!/usr/bin/env python3
"""Retained matched-input localization of the fixed official B numerical failure."""
import argparse
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Integer, ONE, Q
from numerical_diagnostic import observed
from official_weights import OfficialFixture, OfficialFP32, fp32, load_official
from verify import ROOT, Run


def flatten(value):
    if isinstance(value, (list, tuple)):
        return [v for item in value for v in flatten(item)]
    return [value]


def floating(value):
    if isinstance(value, (list, tuple)):
        return [floating(v) for v in value]
    return value/ONE


def diagnose(run):
    run.tools(("python3",))
    tensors, manifest, validation = load_official(ROOT/"hf_embeddinggemma2_vision_spec")
    report = {"input_validation": validation, "cases": [],
              "scope": "advisory localization, not functional acceptance"}
    for mode in (1, 2):
        fixture = OfficialFixture(CONFIGS["B"], 17, mode, 12, tensors, manifest)
        integer, fp = observed(Integer), OfficialFP32()
        it, ft = {}, {}
        output, _ = fixture.run(integer, trace=it)
        software, _ = fixture.run(fp, trace=ft)
        checkpoints = []
        for name, values in it.items():
            actual, expected = flatten(floating(values)), flatten(ft[name])
            assert len(actual) == len(expected)
            checkpoints.append({
                "stage": name, "max_absolute_error": max(abs(a-b) for a, b in zip(actual, expected)),
                "integer_q840": values, "software_fp32": ft[name],
            })
        local = []
        for index, call in enumerate(integer.calls):
            name, args = call["operator"], list(call["args"])
            if name in ("scale", "rotate"):
                args[0] = floating(args[0])
            elif name == "attention":
                args[:3] = [floating(a) for a in args[:3]]
            else:
                args = [None if a is None else floating(a) for a in args]
            expected = getattr(fp, name)(*args, **call["kwargs"])
            actual = flatten(floating(call["result"]))
            error = max(abs(a-b) for a, b in zip(actual, flatten(expected)))
            local.append({
                "call": index, "operator": name, "matched_input_error": error,
                "integer_operands_q840": call["args"], "kwargs": call["kwargs"],
                "integer_result_q840": call["result"], "matched_input_fp32": expected,
            })
            if name == "norm" and len(args) > 1 and args[1] is not None:
                x, w = args
                denominator = math.sqrt(sum(a*a for a in x)/len(x)+17/Q)
                counterfactual = [fp32(a/denominator*(1+b)) for a, b in zip(x, w)]
                local[-1]["same_hardware_epsilon_counterfactual"] = {
                    "acceptance_reference_changed": False,
                    "epsilon": 17/Q,
                    "max_absolute_error": max(abs(a-b) for a, b in zip(actual, counterfactual)),
                    "rms_input_square_mean": sum(a*a for a in x)/len(x),
                }
        report["cases"].append({
            "mode": mode, "seed": 17, "checkpoints": checkpoints,
            "worst_local_operations": sorted(
                local, key=lambda c: c["matched_input_error"], reverse=True)[:20],
            "max_output_error": max(abs(a/Q-b) for a, b in zip(output, software)),
        })
        (run.directory/"localization.json").write_text(json.dumps(report, indent=2)+"\n")
        run.receipt["assertions"].append({
            "mode": mode, "operator_calls_examined": len(local),
            "checkpoints_compared": len(checkpoints),
            "max_output_error": report["cases"][-1]["max_output_error"],
        })
        run.save()
        print(json.dumps({
            "mode": mode,
            "checkpoints": [{k: c[k] for k in ("stage", "max_absolute_error")}
                            for c in checkpoints],
            "worst_local": [{k: c[k] for k in (
                "call", "operator", "matched_input_error", "same_hardware_epsilon_counterfactual")
                if k in c}
                            for c in report["cases"][-1]["worst_local_operations"][:3]],
        }), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repair-of", required=True)
    args = parser.parse_args()
    directory = (ROOT/args.output).resolve()
    assert directory.is_relative_to(ROOT/"evidence/preparation")
    run = Run(directory, repair_of=args.repair_of)
    try:
        diagnose(run)
    except Exception as error:
        run.finish("failed", str(error))
        raise
    run.finish("diagnosis_completed_not_acceptance")


if __name__ == "__main__":
    main()
