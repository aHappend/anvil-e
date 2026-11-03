"""Portable L1 entrypoint. A successful child is not, by itself, coverage closure."""

import sys

sys.dont_write_bytecode = True

import argparse
import hashlib
import json
import shutil
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


SUITES = ("contract", "behavior", "defects", "benchmark", "synthesis", "portable")
SEEDS = (17, 43, 89)
DOMAINS = ("text", "image+text", "audio+text", "image/audio/text", "long-context")
DEFECTS = (
    "wrong-anchor", "shared-kv-computation", "duplicate-ddr-fetch",
    "stale-generation", "e2b-double-width-omission", "q4-nibble-order",
    "missing-ple-gating", "missing-final-softcap", "stalled-payload-corruption",
    "csr-clear-priority", "replay-spill", "missing-live-frame-allocation",
)
TOOLS = {
    "contract": ("python3", "iverilog", "vvp", "verilator", "make", "g++"),
    "behavior": ("python3", "iverilog", "vvp", "verilator", "make", "g++"),
    "defects": ("python3", "verilator", "make", "g++"),
    "benchmark": ("python3", "verilator", "make", "g++"),
    "synthesis": ("python3", "yosys"),
    "portable": ("python3", "iverilog", "vvp", "yosys"),
}


@dataclass(frozen=True)
class Step:
    name: str
    script: str
    arguments: tuple = ()


def steps(suite, seeds=SEEDS):
    """Every dependency is executed in this invocation, without historical receipts."""
    if suite == "contract":
        return [
            Step("top-protocol", "run_top_contract.py"),
            Step("weight-portability", "run_weight_read.py",
                 ("--compact", "--simulator", "iverilog")),
            Step("owner-portability", "run_owner_icarus.py"),
            Step("csr", "run_csr.py"),
            Step("workspace", "run_workspace.py"),
            *[Step(f"cache-c{capacity}", "run_arithmetic.py",
                   ("--target", "cache", "--capacity", str(capacity),
                    "--simulator", "verilator")) for capacity in (1, 3, 64)],
            Step("directory", "run_tensor_image.py"),
            Step("directory-production", "run_tensor_lifetime.py", ("--production",)),
        ]
    if suite == "behavior":
        return [
            *[Step(target, "run_arithmetic.py",
                   ("--target", target, "--simulator", "verilator", "--exhaustive"))
              for target in ("arithmetic", "activation", "norm")],
            Step("weights", "run_weight_read.py"),
            Step("projection", "run_projection.py"),
            Step("rotary", "run_rotary.py"),
            Step("owner", "run_owner_tile.py"),
            Step("owner-production", "run_owner_production.py"),
            Step("allocation-bounds", "run_allocation.py"),
            Step("allocation-ledger", "run_ledger_matrix.py"),
            Step("allocation-schedule", "run_ledger_schedule.py",
                 ("--simulator", "both")),
            Step("baseline", "run_baseline.py", ("--seeds", ",".join(map(str, seeds)))),
            *[Step(f"top-m{model}-p{precision}-s{seed}-c{capacity}-f{fallback}",
                   "run_top_smoke.py",
                   ("--model", str(model), "--precision", str(precision),
                    "--seed", str(seed), "--capacity", str(capacity),
                    "--split-schedule", *(("--fallback",) if fallback else ())))
              for model in (1, 2) for precision in (0, 1) for seed in seeds
              for capacity in (1, 3, 64) for fallback in (0, 1)],
        ]
    if suite == "defects":
        return [
            Step("anchors", "run_cache_defect.py"),
            Step("owners", "run_owner_tile.py", ("--defects",)),
            Step("q4", "run_weight_read.py", ("--compact", "--defect")),
            Step("csr", "run_csr.py", ("--defect", "--simulator", "verilator")),
            Step("workspace", "run_workspace.py", ("--defects", "--simulator", "verilator")),
            Step("allocation", "run_ledger_matrix.py",
                 ("--defect", "missing-live-frame-allocation")),
            Step("reader", "run_reader_defects.py"),
        ]
    if suite == "benchmark":
        # These are executable text prerequisites, not substitutes for native
        # modality observations. close_coverage enforces all five domains.
        return [
            Step("baseline", "run_baseline.py"),
            *[Step(f"text-m{model}-p{precision}", "run_top_smoke.py",
                   ("--model", str(model), "--precision", str(precision),
                    "--capacity", "64", "--split-schedule"))
              for model in (1, 2) for precision in (0, 1)],
        ]
    if suite == "synthesis":
        return [
            Step("connected-production", "run_synthesis.py", ("--compact-parent",)),
            Step("workspace-production", "run_workspace.py", ("--synthesis",)),
        ]
    if suite == "portable":
        return []
    raise ValueError("unknown suite: " + suite)


def parse_result(output, root):
    """Only accept the exact receipt advertised by the just-executed child."""
    lines = [line for line in output.splitlines() if line.strip()]
    if not lines:
        raise RuntimeError("child produced no result")
    result = json.loads(lines[-1])
    path = Path(result["receipt"])
    if path.is_absolute() or ".." in path.parts:
        raise RuntimeError("child advertised a non-project-relative receipt")
    receipt = json.loads((root / path).read_text())
    if (result["status"] != "passed" or receipt["status"] != "passed"
            or receipt["exit_code"] != 0 or not receipt.get("ended_at")):
        raise RuntimeError("child did not settle successfully: " + str(path))
    if not receipt.get("commands"):
        raise RuntimeError("child retained no tool executions")
    for command in receipt["commands"]:
        if (command.get("timed_out") is not False or not command.get("ended_at")
                or command.get("exit_code") not in command.get("expected_exit_codes", [0])):
            raise RuntimeError("child has an unsuccessful tool execution: " + str(path))
        for channel in ("stdout", "stderr"):
            log = Path(command[channel])
            if log.is_absolute() or ".." in log.parts or not (root / log).is_file():
                raise RuntimeError("child raw log is absent or not project-relative")
    return path, receipt


def require_source_identity(receipt, sources):
    for name, digest in sources.items():
        if receipt["source_sha256"].get(name) != digest:
            raise RuntimeError("child source binding differs: " + name)


def require_child_sources(receipt, sources):
    require_source_identity(
        receipt, {name: digest for name, digest in sources.items() if name.startswith("tests/")})
    for name, digest in receipt["source_sha256"].items():
        if sources.get(name) != digest:
            raise RuntimeError("child source is outside the frozen input set: " + name)


def require_cases(records, required, fields, label):
    """Coverage comes from completed public comparisons, never from launch labels."""
    observed = set()
    for record in records:
        for case in record.get("observations", []):
            if (case.get("kind") == label and case.get("comparisons", 0) > 0
                    and case.get("completed") is True
                    and case.get("mismatches") == 0):
                observed.add(tuple(case[field] for field in fields))
    missing = set(required) - observed
    if missing:
        first = sorted(missing, key=repr)[0]
        raise RuntimeError(
            f"{label}: {len(missing)} required completed comparison cells absent; first={first}")
    return len(observed)


def close_coverage(suite, records, seeds):
    """The incomplete integration/benchmark matrix cannot produce a false L1 pass."""
    counts = {}
    if suite == "behavior":
        required = [(m, p, s, c, n, f) for m in (1, 2) for p in (0, 1)
                    for s in seeds for c in (1, 3, 64)
                    for n, f in ((1, 0), (16, 0), (17, 0), (1, 1), (17, 1))]
        counts["top"] = require_cases(
            records, required, ("model", "precision", "seed", "capacity", "tokens", "fallback"),
            "top-numerical")
        counts["top-integration"] = require_cases(
            records, required, ("model", "precision", "seed", "capacity", "tokens", "fallback"),
            "top-integration-allocation-traffic")
        counts["fallback-history"] = require_cases(
            records, [(m, p, a) for m in (1, 2) for p in (0, 1) for a in ("local", "global")],
            ("model", "precision", "attention"), "eval-2-1-history")
        counts["production-cache"] = require_cases(
            records, [(m, p, c, n) for m in (1, 2) for p in (0, 1)
                      for c in (1, 3, 64) for n in (1, 16, 17, 511, 512, 513, 1025)],
            ("model", "precision", "capacity", "tokens"), "production-cache-rematerialization")
    elif suite == "defects":
        counts["defects"] = require_cases(
            records, [(name,) for name in DEFECTS], ("defect",), "intended-mutation-rejection")
    elif suite == "benchmark":
        counts["domains"] = require_cases(
            records, [(d, m, p) for d in DOMAINS for m in (1, 2) for p in (0, 1)],
            ("domain", "model", "precision"), "five-domain-top-numerical")
    return counts


def execute_step(exp, step):
    output = exp.run(
        step.name,
        [sys.executable, "-B", "tests/" + step.script, *step.arguments,
         "--out", str(exp.relative / step.name)],
        timeout=2700)
    path, receipt = parse_result(output, ROOT)
    if exp.relative not in path.parents:
        raise RuntimeError("child receipt is outside this fresh run")
    # Leaf runners sometimes bind only their RTL subset, but all bind tests.
    require_child_sources(receipt, exp.receipt["source_sha256"])
    exp.receipt["children"].append({
        "name": step.name, "receipt": str(path),
        "sha256": hashlib.sha256((ROOT / path).read_bytes()).hexdigest(),
    })
    exp.save()
    return receipt


def reproduce(exp):
    destination = exp.out / "reproduction"
    destination.mkdir()
    copied = {}
    for source in source_inputs():
        if not source.is_file():
            continue
        relative = source.relative_to(ROOT)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if digest != exp.receipt["source_sha256"][str(relative)]:
            raise RuntimeError("reproduction copy differs: " + str(relative))
        copied[str(relative)] = digest
    exp.receipt["reproduction_source_sha256"] = copied
    exp.save()
    # cwd belongs to the copied tree; no original binary or previous receipt is used.
    for label, script, arguments in (
            ("arithmetic", "run_arithmetic.py", ("--simulator", "iverilog")),
            ("synthesis", "run_synthesis.py", ("--compact-parent",))):
        output = exp.run(
            "reproduce-" + label,
            [sys.executable, "-B", "tests/" + script, *arguments,
             "--out", "evidence/" + label],
            timeout=2700, cwd=destination)
        path, receipt = parse_result(output, destination)
        require_child_sources(receipt, copied)
        exp.receipt["children"].append({
            "name": "reproduce-" + label,
            "receipt": str(destination.relative_to(ROOT) / path),
            "sha256": hashlib.sha256((destination / path).read_bytes()).hexdigest(),
        })
        exp.save()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUITES, required=True)
    parser.add_argument("--seeds", default="17,43,89")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    if args.seeds != "17,43,89":
        parser.error("--seeds must retain the complete frozen order 17,43,89")
    prefix = Path(args.out)
    if prefix.is_absolute() or ".." in prefix.parts or not prefix.parts:
        parser.error("--out must be a nonempty project-relative prefix")
    # Existing regular files remain errors; retrying a directory retains its children.
    prefix_path = ROOT / prefix
    prefix_path.mkdir(parents=True, exist_ok=True)
    exp = Experiment(str(prefix / "run"), "l1-" + args.suite, source_inputs())
    exp.receipt["children"] = []
    exp.receipt["suite"] = args.suite
    exp.receipt["seeds"] = list(SEEDS)
    exp.save()
    error = None
    try:
        for tool in TOOLS[args.suite]:
            option = "-V" if tool in ("iverilog", "vvp", "yosys") else "--version"
            exp.run(tool + "-version", [tool, option], timeout=30)
        if args.suite == "portable":
            reproduce(exp)
        else:
            records = [execute_step(exp, step) for step in steps(args.suite)]
            exp.receipt["coverage_counts"] = close_coverage(args.suite, records, SEEDS)
        for name, digest in exp.receipt["source_sha256"].items():
            if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
                raise RuntimeError("verification input changed during execution: " + name)
        if time.monotonic() > exp.deadline:
            raise TimeoutError("complete L1 suite exceeded its 2700-second budget")
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
