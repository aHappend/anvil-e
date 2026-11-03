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


ROOT = Path(__file__).resolve().parents[1]


def stamp():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/arithmetic")
    parser.add_argument("--simulator", choices=("iverilog", "verilator"), default="iverilog")
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
        "kind": "verifier-arithmetic-preparation",
        "argv": [sys.executable, *sys.argv],
        "cwd": ".",
        "started_at": stamp(),
        "timeout_s": 2700,
        "repair_of": args.repair_of,
        "source_sha256": {},
        "commands": [],
        "status": "running",
    }
    inputs = [ROOT / "rtl/anvil_en1_fp32.sv", ROOT / "rtl/anvil_en1_fp32_divsqrt.sv",
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
        if simulator == "iverilog":
            binary = str(relative / "arithmetic.vvp")
            run("compile", ["iverilog", "-g2012", "-Wall", "-s", "arithmetic_tb",
                            "-o", binary, *sources], 600)
            command = ["vvp", binary]
        else:
            obj = relative / "compile-obj"
            run("compile", ["verilator", "--binary", "--timing", "-Wno-fatal",
                            "--top-module", "arithmetic_tb", "--Mdir", str(obj),
                            "-j", "2", *sources], 1800)
            command = [str(obj / "Varithmetic_tb")]
        command += ["+vectors=" + str(vectors.relative_to(ROOT)),
                    "+max_cycles=" + ("30000000" if args.exhaustive else "500000")]
        output = run("simulation", command, 600 if simulator == "iverilog" else 2400)
        marker = f"SUMMARY arithmetic comparisons={count} "
        if marker not in output:
            raise RuntimeError("simulation lacks exact nonzero completion comparison count")
        receipt["status"] = "passed"
        receipt["comparison_count"] = count
        receipt["summary"] = next(line for line in output.splitlines() if marker in line)
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
