"""Bounded independent arithmetic diagnostic, with immutable per-run receipts."""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from numerical_reference import arithmetic_vectors
from activation_reference import activation_vectors
from norm_reference import norm_cases


ROOT = Path(__file__).resolve().parents[1]


def stamp():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/arithmetic")
    parser.add_argument("--simulator", choices=("iverilog", "verilator"), default="iverilog")
    parser.add_argument("--target", choices=("arithmetic", "cache", "activation", "norm"),
                        default="arithmetic")
    parser.add_argument("--capacity", type=int, choices=(1, 3, 64), default=3)
    parser.add_argument("--exhaustive", action="store_true")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    prefix = Path(args.out)
    if prefix.is_absolute() or ".." in prefix.parts:
        parser.error("--out must be a project-relative prefix")
    if args.exhaustive and args.simulator != "verilator":
        args.simulator = "verilator"
    out = ROOT / (str(prefix) + "-" +
                  datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") +
                  "-" + uuid.uuid4().hex[:8])
    out.mkdir(parents=True, exist_ok=False)
    relative = out.relative_to(ROOT)
    receipt = {
        "kind": "verifier-leaf-preparation",
        "argv": list(sys.orig_argv),
        "cwd": ".",
        "started_at": stamp(),
        "timeout_s": 2700,
        "repair_of": args.repair_of,
        "source_sha256": {},
        "commands": [],
        "status": "running",
        "configuration": vars(args),
    }
    inputs = [ROOT / "rtl/anvil_en1_fp32.sv", ROOT / "rtl/anvil_en1_fp32_divsqrt.sv",
              ROOT / "rtl/anvil_en1_kv_shared_cache.sv", ROOT / "rtl/anvil_en1_geometry.sv",
              ROOT / "rtl/anvil_en1_activation.sv", ROOT / "rtl/anvil_en1_exp.sv",
              ROOT / "rtl/anvil_en1_norm.sv", ROOT / "rtl/anvil_en1_uint_to_fp32.sv",
              *sorted((ROOT / "tests").glob("*"))]
    for path in inputs:
        if path.is_file():
            receipt["source_sha256"][str(path.relative_to(ROOT))] = (
                hashlib.sha256(path.read_bytes()).hexdigest())
    deadline = time.monotonic() + 2700

    def save():
        (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")

    def run(label, argv, timeout):
        command = {"argv": argv, "cwd": ".", "started_at": stamp(),
                   "timeout_s": timeout, "stdout": str(relative / (label + ".stdout.txt")),
                   "stderr": str(relative / (label + ".stderr.txt"))}
        receipt["commands"].append(command)
        save()
        try:
            with (ROOT / command["stdout"]).open("w") as stdout, (
                    ROOT / command["stderr"]).open("w") as stderr:
                result = subprocess.run(argv, cwd=ROOT, stdout=stdout, stderr=stderr,
                                        timeout=min(timeout, max(1, deadline-time.monotonic())),
                                        check=False)
            command["exit_code"] = result.returncode
            command["timed_out"] = False
        except subprocess.TimeoutExpired:
            command["exit_code"] = None
            command["timed_out"] = True
            raise
        finally:
            command["ended_at"] = stamp()
            save()
        if result.returncode != 0:
            raise RuntimeError(f"{label} exited {result.returncode}: {command['stdout']}")
        return (ROOT / command["stdout"]).read_text()

    exit_code = 1
    try:
        simulator = args.simulator
        for label, command in (
                ("python-version", [sys.executable, "--version"]),
                ("simulator-version", [simulator, "-V"])):
            run(label, command, 30)
        if simulator == "iverilog":
            run("vvp-version", ["vvp", "-V"], 30)
        if args.target == "arithmetic":
            vectors = out / "vectors.txt"
            count = 0
            with vectors.open("w") as stream:
                for row in arithmetic_vectors(exhaustive=args.exhaustive):
                    index, engine, operation, a, b, expected, error, stall = row
                    stream.write(f"{index} {engine} {operation} {a:08x} {b:08x} "
                                 f"{expected:08x} {error} {stall}\n")
                    count += 1
            receipt["fixtures"] = {
                "path": str(vectors.relative_to(ROOT)), "count": count,
                "sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
                "seeds": [17, 43, 89], "expected_computed_before_observation": True,
                "reference": "exact rational arithmetic and squared midpoint rounding",
            }
            sources = ["tests/arithmetic_tb.sv", "rtl/anvil_en1_fp32.sv",
                       "rtl/anvil_en1_fp32_divsqrt.sv"]
        elif args.target == "activation":
            vectors = out / "vectors.txt"
            count = 0
            with vectors.open("w") as stream:
                for row in activation_vectors(dense=args.exhaustive):
                    index, operation, word, lower, upper, error, stall, exact = row
                    stream.write(f"{index} {operation} {word:08x} {lower:08x} "
                                 f"{upper:08x} {error} {stall} {exact}\n")
                    count += 1
            receipt["fixtures"] = {
                "path": str(vectors.relative_to(ROOT)), "count": count,
                "sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
                "expected_computed_before_observation": True,
                "reference": "binary64 transcendentals; inward-rounded contract intervals",
            }
            sources = ["tests/activation_tb.sv", "rtl/anvil_en1_activation.sv",
                       "rtl/anvil_en1_exp.sv", "rtl/anvil_en1_fp32.sv",
                       "rtl/anvil_en1_fp32_divsqrt.sv"]
        elif args.target == "norm":
            vectors = out / "vectors.txt"
            count = 0
            with vectors.open("w") as stream:
                for case in norm_cases(production=args.exhaustive):
                    index, layer_norm, learned, source, scales, expected = case
                    stream.write(f"{index} {layer_norm} {learned} {len(source)}\n")
                    for value, scale, result in zip(source, scales, expected):
                        stream.write(f"{value:04x} {scale:04x} {result:04x}\n")
                    count += 1
            receipt["fixtures"] = {
                "path": str(vectors.relative_to(ROOT)), "count": count,
                "sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
                "seeds": [17, 43, 89], "expected_computed_before_observation": True,
                "reference": "exact independently ordered reductions and once-rounded reciprocal root",
            }
            sources = ["tests/norm_tb.sv", "rtl/anvil_en1_norm.sv",
                       "rtl/anvil_en1_uint_to_fp32.sv", "rtl/anvil_en1_fp32.sv",
                       "rtl/anvil_en1_fp32_divsqrt.sv"]
        else:
            count = None
            receipt["fixtures"] = {
                "source": "tests/cache_tb.sv",
                "capacity": args.capacity,
                "reference": "ABI owner schedule and independent transaction FIFO of resident keys",
            }
            sources = ["tests/cache_tb.sv", "rtl/anvil_en1_kv_shared_cache.sv",
                       "rtl/anvil_en1_geometry.sv"]
        top = args.target + "_tb"
        if simulator == "iverilog":
            binary = str(relative / (args.target + ".vvp"))
            parameters = ([f"-P{top}.CAPACITY={args.capacity}"] if args.target == "cache" else [])
            run("compile", ["iverilog", "-g2012", "-Wall", "-s", top,
                            *parameters, "-o", binary, *sources], 600)
            command = ["vvp", binary]
        else:
            obj = relative / "compile-obj"
            parameters = ([f"-GCAPACITY={args.capacity}"] if args.target == "cache" else [])
            run("compile", ["verilator", "--binary", "--timing", "-Wno-fatal",
                            "--top-module", top, "--Mdir", str(obj),
                            "-j", "2", *parameters, *sources], 1800)
            command = [str(obj / ("V" + top))]
        if args.target in ("arithmetic", "activation", "norm"):
            command += ["+vectors=" + str(vectors.relative_to(ROOT)),
                        "+max_cycles=" + ("100000000" if args.exhaustive else "500000")]
        output = run("simulation", command, 600 if simulator == "iverilog" else 2400)
        marker = (f"SUMMARY {args.target} comparisons={count} " if args.target != "cache" else
                  f"SUMMARY cache capacity={args.capacity} ")
        if args.target == "norm":
            marker = f"SUMMARY norm cases={count} "
        if marker not in output:
            raise RuntimeError("simulation lacks exact nonzero completion comparison count")
        receipt["status"] = "passed"
        receipt["summary"] = next(line for line in output.splitlines() if marker in line)
        fields = dict(item.split("=", 1) for item in receipt["summary"].split()[2:])
        receipt["observed_counts"] = {key: int(value) for key, value in fields.items()}
        receipt["comparison_count"] = (int(fields["comparisons"]) if "comparisons" in fields
                                       else int(fields["meta"]) + int(fields["fetch"]))
        exit_code = 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        receipt["status"] = "failed"
        receipt["failure"] = str(exc)
    finally:
        receipt["ended_at"] = stamp()
        receipt["exit_code"] = exit_code
        save()
        objects = out / "compile-obj"
        if objects.exists():
            shutil.rmtree(objects)
    print(json.dumps({"status": receipt["status"],
                      "receipt": str(relative / "receipt.json"),
                      "failure": receipt.get("failure")}), flush=True)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
