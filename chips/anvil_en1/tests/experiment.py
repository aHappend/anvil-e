"""Project-relative, bounded tool execution with immutable per-run receipts."""

import hashlib
import json
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
            "kind": kind, "argv": [sys.executable, *sys.argv], "cwd": ".",
            "started_at": timestamp(), "timeout_s": 2700, "repair_of": repair_of,
            "source_sha256": {str(path.relative_to(ROOT)):
                              hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in sources if path.is_file()},
            "commands": [], "status": "running",
        }
        self.save()

    def save(self):
        (self.out / "receipt.json").write_text(json.dumps(self.receipt, indent=2) + "\n")

    def run(self, label, argv, timeout=2400, expected_exit_codes=(0,)):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("complete experiment exceeded 2700-second execution budget")
        effective = min(timeout, remaining)
        command = {
            "argv": argv, "cwd": ".", "started_at": timestamp(),
            "timeout_s": effective,
            "stdout": str(self.relative / (label + ".stdout.txt")),
            "stderr": str(self.relative / (label + ".stderr.txt")),
            "expected_exit_codes": list(expected_exit_codes),
        }
        self.receipt["commands"].append(command)
        self.save()
        try:
            with (ROOT / command["stdout"]).open("w") as stdout, (
                    ROOT / command["stderr"]).open("w") as stderr:
                # Poll only the launched child to emit bounded phase heartbeats.
                with subprocess.Popen(argv, cwd=ROOT, stdout=stdout, stderr=stderr) as child:
                    started = time.monotonic()
                    while True:
                        elapsed = time.monotonic() - started
                        try:
                            code = child.wait(timeout=min(30, max(0.001, effective-elapsed)))
                            break
                        except subprocess.TimeoutExpired:
                            if time.monotonic() - started >= effective:
                                child.kill()
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


def source_inputs():
    return [*sorted((ROOT / "rtl").glob("*.sv")),
            *sorted((ROOT / "anvil_e3_reference/rtl").glob("*.sv")),
            ROOT / "design/SPEC.md", ROOT / "design/ARCHITECTURE.md",
            *[path for path in sorted((ROOT / "tests").glob("*")) if path.is_file()]]
