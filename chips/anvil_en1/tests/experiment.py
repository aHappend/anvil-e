"""Project-relative, bounded tool execution with immutable per-run receipts."""

import hashlib
import json
import os
import signal
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def timestamp():
    return datetime.now(timezone.utc).isoformat()


class Experiment:
    def __init__(self, prefix, kind, sources, repair_of=None):
        prefix = Path(prefix)
        if prefix.is_absolute() or ".." in prefix.parts:
            raise ValueError("output must be a project-relative prefix")
        self.relative = Path(str(prefix) + "-" +
                             datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") +
                             "-" + uuid.uuid4().hex[:8])
        self.out = ROOT / self.relative
        self.out.mkdir(parents=True, exist_ok=False)
        self.deadline = time.monotonic() + 2700
        self.receipt = {
            "kind": kind, "argv": list(sys.orig_argv), "cwd": ".",
            "started_at": timestamp(), "timeout_s": 2700, "repair_of": repair_of,
            "source_sha256": {str(path.relative_to(ROOT)):
                              hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sources if path.is_file()},
            "commands": [], "status": "running",
        }
        self.save()

    def save(self):
        (self.out / "receipt.json").write_text(json.dumps(self.receipt, indent=2) + "\n")

    def run(self, label, argv, timeout=2400, expected_exit_codes=(0,), cwd=None):
        if any(Path(command["stdout"]).name == label + ".stdout.txt"
               for command in self.receipt["commands"]):
            raise ValueError("command label already retained: " + label)
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("complete experiment exceeded 2700-second execution budget")
        effective = min(timeout, remaining)
        directory = ROOT if cwd is None else Path(cwd).resolve()
        relative_cwd = directory.relative_to(ROOT)
        command = {
            "argv": argv, "cwd": str(relative_cwd), "started_at": timestamp(),
            "timeout_s": effective,
            "stdout": str(self.relative / (label + ".stdout.txt")),
            "stderr": str(self.relative / (label + ".stderr.txt")),
            "expected_exit_codes": list(expected_exit_codes),
        }
        self.receipt["commands"].append(command)
        self.save()
        nested_scope = os.environ.get("ANVIL_EXPERIMENT_SCOPE") == "1"
        child = None
        try:
            with (ROOT / command["stdout"]).open("w") as stdout, (
                    ROOT / command["stderr"]).open("w") as stderr:
                # Poll only the launched child to emit bounded phase heartbeats.
                with subprocess.Popen(
                        argv, cwd=directory, stdout=stdout, stderr=stderr,
                        start_new_session=not nested_scope,
                        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1",
                             "ANVIL_EXPERIMENT_SCOPE": "1"}) as child:
                    started = time.monotonic()
                    while True:
                        elapsed = time.monotonic() - started
                        try:
                            code = child.wait(timeout=min(30, max(0.001, effective-elapsed)))
                            break
                        except subprocess.TimeoutExpired:
                            if time.monotonic() - started >= effective:
                                if nested_scope:
                                    child.kill()
                                else:
                                    os.killpg(child.pid, signal.SIGKILL)
                                child.wait()
                                command["exit_code"] = child.returncode
                                command["timed_out"] = True
                                raise TimeoutError(f"{label} exceeded its recorded timeout")
                            print(f"PROGRESS phase={label} elapsed_s={int(time.monotonic()-started)} "
                                  f"receipt={self.relative}/receipt.json", flush=True)
            command["exit_code"] = code
            command["timed_out"] = False
        except OSError as exc:
            command["launch_error"] = str(exc)
            raise
        finally:
            if child is not None and not nested_scope:
                # Nested runners inherit this command's group, so compilers
                # cannot outlive a failed or timed-out wrapper.
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            command["ended_at"] = timestamp()
            self.save()
        if code not in expected_exit_codes:
            raise RuntimeError(f"{label} exited {code}; see {command['stderr']}")
        return (ROOT / command["stdout"]).read_text()

    def finish(self, error=None):
        self.receipt.update(status="failed" if error else "passed",
                            ended_at=timestamp(), exit_code=1 if error else 0)
        if error:
            self.receipt["failure"] = str(error)
        self.save()
        print(json.dumps({"status": self.receipt["status"],
                          "receipt": str(self.relative / "receipt.json"),
                          "failure": self.receipt.get("failure")}), flush=True)
        return self.receipt["exit_code"]

    def record_rejection(self, defect, assertion, clean, mutant):
        commands = {Path(command["stdout"]).name.removesuffix(".stdout.txt"): command
                    for command in self.receipt["commands"]}
        for label in (*clean, *mutant):
            command = commands[label]
            if command.get("timed_out") is not False or not command.get("ended_at"):
                raise RuntimeError("mutation command did not settle: " + label)
        if any(commands[label]["exit_code"] != 0 for label in (*clean, mutant[0])):
            raise RuntimeError("mutation lacks successful compilation and unmodified control")
        failed = commands[mutant[1]]
        if failed["exit_code"] == 0:
            raise RuntimeError("mutant was not rejected: " + defect)
        diagnostic = "".join((ROOT / failed[channel]).read_text()
                             for channel in ("stdout", "stderr"))
        if assertion not in diagnostic:
            raise RuntimeError("mutant missed its intended assertion: " + defect)
        self.receipt.setdefault("observations", []).append({
            "kind": "intended-mutation-rejection", "defect": defect,
            "assertion": assertion, "completed": True,
            "unmodified_completed": True, "compiled": True,
            "rejected_by_intended_assertion": True,
            "commands": [*clean, *mutant],
        })
        self.save()


def source_inputs():
    return [*sorted((ROOT / "rtl").glob("*.sv")),
            *sorted((ROOT / "anvil_e3_reference/rtl").glob("*.sv")),
            ROOT / "design/SPEC.md", ROOT / "design/ARCHITECTURE.md",
            *[path for path in sorted((ROOT / "tests").glob("*")) if path.is_file()]]
