"""Single-token compact public-top diagnostic; not full L1 coverage."""

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
from numerical_reference import decode
from text_fixture import make_text_image
from text_reference import logits


ROOT = Path(__file__).resolve().parents[1]


def stamp():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/top-smoke")
    parser.add_argument("--model", type=int, choices=(1, 2), default=1)
    parser.add_argument("--precision", type=int, choices=(0, 1), default=0)
    parser.add_argument("--seed", type=int, choices=(17, 43, 89), default=17)
    parser.add_argument("--capacity", type=int, choices=(1, 3, 64), default=3)
    parser.add_argument("--fallback", action="store_true")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    prefix = Path(args.out)
    if prefix.is_absolute() or ".." in prefix.parts:
        parser.error("--out must be a project-relative prefix")
    relative = Path(str(prefix) + "-" +
                    datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") +
                    "-" + uuid.uuid4().hex[:8])
    out = ROOT / relative
    out.mkdir(parents=True, exist_ok=False)
    receipt = {
        "kind": "verifier-top-preparation",
        "argv": [sys.executable, *sys.argv],
        "cwd": ".",
        "started_at": stamp(),
        "timeout_s": 2700,
        "repair_of": args.repair_of,
        "source_sha256": {},
        "commands": [],
        "status": "running",
        "configuration": vars(args),
    }
    inputs = [*sorted((ROOT / "rtl").glob("*.sv")),
              *sorted((ROOT / "anvil_e3_reference/rtl").glob("*.sv")),
              ROOT / "design/SPEC.md", ROOT / "design/ARCHITECTURE.md",
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
            raise RuntimeError(f"{label} exited {result.returncode}: {command['stderr']}")
        return (ROOT / command["stdout"]).read_text()

    code = 1
    try:
        for label, command in (
                ("python-version", [sys.executable, "--version"]),
                ("verilator-version", ["verilator", "--version"]),
                ("cxx-version", ["g++", "--version"]),
                ("make-version", ["make", "--version"])):
            run(label, command, 30)
        image, tensors = make_text_image(args.model, args.precision, args.seed)
        (out / "image.bin").write_bytes(image)
        expected = logits(tensors, args.model, args.seed)
        (out / "expected.json").write_text(json.dumps(expected, indent=2) + "\n")
        receipt["fixtures"] = {
            name: hashlib.sha256((out / name).read_bytes()).hexdigest()
            for name in ("image.bin", "expected.json")
        }
        receipt["expected_computed_before_observation"] = True
        save()
        sources = [str(path.relative_to(ROOT)) for path in inputs
                   if path.suffix == ".sv" and path.parent != ROOT / "tests"]
        obj = relative / "compile-obj"
        # Native geometry remains all 35/42 layers; these parameters affect only model 0.
        parent = {"TEXT_LAYERS": 1, "TEXT_HIDDEN": 8, "TEXT_FFN": 16, "PLE_DIM": 4,
                  "EMBED_DIM": 12, "VOCAB_SIZE": 32, "MAX_SEQ_LEN": 32,
                  "TEXT_Q_HEADS": 2, "LOCAL_KV_HEADS": 1, "FULL_KV_HEADS": 1,
                  "LOCAL_HEAD_DIM": 4, "FULL_HEAD_DIM": 8, "SLIDING_WINDOW": 4,
                  "POSITION_EMBEDDING_SIZE": 32}
        parameters = {"COMPACT": 1, "RESIDENT_ENTRIES": args.capacity,
                      "FORCE_FALLBACK": int(args.fallback), **parent}
        command = ["verilator", "--cc", "--exe", "--build", "-Wno-fatal",
                   "--top-module", "anvil_en1_top", "--Mdir", str(obj),
                   "-j", "2", "-CFLAGS", "-O1"]
        command += [f"-G{key}={value}" for key, value in parameters.items()]
        command += [*sources, str(ROOT / "tests/top_smoke.cpp")]
        run("compile", command, 1800)
        output = run("simulation", [str(obj / "Vanvil_en1_top"),
                                   str(relative / "image.bin"), str(args.model),
                                   str(args.precision), str(args.seed), "2000000000"], 2400)
        observed = []
        for line in output.splitlines():
            if line.startswith("LOGIT "):
                _, index, value = line.split()
                if int(index) != len(observed):
                    raise RuntimeError("out-of-order observed logit")
                sign, category, number = decode(int(value), 8, 7)
                if category != "finite":
                    raise RuntimeError("nonfinite fixture output")
                observed.append(float(number))
        if len(observed) != 32 or "SUMMARY top logits=32 " not in output:
            raise RuntimeError("incomplete top comparison boundary")
        errors = [abs(actual - reference)
                  for actual, reference in zip(observed, expected["logits"])]
        for index, (error, reference) in enumerate(zip(errors, expected["logits"])):
            if not -30 <= observed[index] <= 30 or error > 0.25 + 0.02 * abs(reference):
                raise RuntimeError(f"logit mismatch index={index} observed={observed[index]} "
                                   f"reference={reference} error={error}")
        receipt["comparison_count"] = 32
        receipt["maximum_logit_absolute_error"] = max(errors)
        receipt["status"] = "passed"
        code = 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        receipt["status"] = "failed"
        receipt["failure"] = str(exc)
    finally:
        receipt["ended_at"] = stamp()
        receipt["exit_code"] = code
        save()
        objects = out / "compile-obj"
        if objects.exists():
            shutil.rmtree(objects)
    print(json.dumps({"status": receipt["status"],
                      "receipt": str(relative / "receipt.json"),
                      "failure": receipt.get("failure")}), flush=True)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
