#!/usr/bin/env python3
"""Independent acceptance entrypoint. Preparation is advisory, never acceptance."""
import argparse
import ctypes
import datetime
import hashlib
import json
import os
import resource
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
INPUTS = ("rtl/*.sv", "design/*.md", "design/*.py", "tests/*.py", "tests/*.sv",
          "hf_embeddinggemma2_spec/*.json", "hf_embeddinggemma2_spec/1_Pooling/config.json")


def identities():
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for pattern in INPUTS for p in sorted(ROOT.glob(pattern))}


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class Execution:
    def __init__(self, output, allowance):
        self.output = ROOT / output
        if self.output.exists():
            retired = ROOT / "evidence" / "preparation" / f"prior-{self.output.name}-{int(time.time() * 1000)}"
            retired.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(self.output), str(retired))
        self.output.mkdir(parents=True, exist_ok=False)
        self.deadline = time.monotonic() + allowance
        self.allowance = allowance
        self.started = stamp()
        self.sources = identities()
        self.children = []
        self.versions = {}
        self.repair_of = None
        # Adopt orphaned tool grandchildren so cleanup can reap the whole tree.
        if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "PR_SET_CHILD_SUBREAPER failed")

    @staticmethod
    def scope(session):
        members = []
        for path in Path("/proc").glob("[0-9]*/stat"):
            try:
                text = path.read_text()
            except FileNotFoundError:
                continue
            fields = text[text.rfind(")") + 2:].split()
            if int(fields[3]) == session:
                members.append({"pid": int(path.parent.name),
                                "start_ticks": fields[19], "state": fields[0]})
        return members

    def settle(self, process, record):
        started = time.monotonic()
        terminated = []
        for sig, allowance in ((signal.SIGTERM, 0.3), (signal.SIGKILL, 1.0)):
            members = self.scope(process.pid)
            for member in members:
                if member["state"] != "Z":
                    try:
                        os.kill(member["pid"], sig)
                        terminated.append({"pid": member["pid"], "signal": int(sig)})
                    except ProcessLookupError:
                        pass
            end = time.monotonic() + allowance
            while time.monotonic() < end:
                process.poll()
                members = self.scope(process.pid)
                for member in members:
                    if member["pid"] != process.pid:
                        try:
                            os.waitpid(member["pid"], os.WNOHANG)
                        except ChildProcessError:
                            pass
                if not self.scope(process.pid):
                    break
                time.sleep(0.01)
            if not self.scope(process.pid):
                break
        remaining = self.scope(process.pid)
        record["exit_code"] = process.poll()
        record["settlement"] = {"settled": not remaining,
            "terminated": terminated, "remaining": remaining,
            "cleanup_s": time.monotonic() - started}
        return not remaining

    def remaining(self):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("phase-wide monotonic deadline exhausted")
        return remaining

    def run(self, name, argv, maximum=None, expected_exit=0):
        timeout = self.remaining()
        if maximum is not None:
            timeout = min(timeout, maximum)
        stdout = self.output / (name + ".stdout.log")
        stderr = self.output / (name + ".stderr.log")
        record = {"argv": list(map(str, argv)), "cwd": str(ROOT),
                  "start": stamp(), "timeout_s": timeout,
                  "stdout": str(stdout.relative_to(ROOT)),
                  "stderr": str(stderr.relative_to(ROOT)), "timed_out": False}
        self.children.append(record)
        process = None
        started = time.monotonic()
        cpu_before = resource.getrusage(resource.RUSAGE_CHILDREN)
        try:
            with stdout.open("wb") as out, stderr.open("wb") as err:
                process = subprocess.Popen(record["argv"], cwd=ROOT, stdout=out,
                                           stderr=err, start_new_session=True)
                record["pid"] = process.pid
                process.wait(timeout=timeout)
            record["exit_code"] = process.returncode
        except subprocess.TimeoutExpired:
            record["timed_out"] = True
            raise TimeoutError(f"{name}: child timeout")
        finally:
            if process is not None:
                settled = self.settle(process, record)
            else:
                settled = True
            record["duration_s"] = time.monotonic() - started
            cpu_after = resource.getrusage(resource.RUSAGE_CHILDREN)
            record["cpu_user_s"] = cpu_after.ru_utime - cpu_before.ru_utime
            record["cpu_system_s"] = cpu_after.ru_stime - cpu_before.ru_stime
            record["end"] = stamp()
            self.save("running")
        if not settled:
            raise RuntimeError(f"{name}: child process tree did not settle")
        if process.returncode != expected_exit:
            raise AssertionError(f"{name}: exit {process.returncode}; see {stderr.relative_to(ROOT)}")
        return stdout

    def prerequisites(self, names):
        for name in names:
            executable = shutil.which(name)
            if executable is None:
                raise RuntimeError(f"missing prerequisite: {name}; installation is not authorized")
            version_arg = "--version" if name == "python3" else "-V"
            log = self.run("version-" + name, [executable, version_arg], maximum=5)
            self.versions[name] = {"path": executable,
                                   "stdout": str(log.relative_to(ROOT))}

    def save(self, status, detail=None):
        receipt = {"argv": sys.argv, "cwd": str(ROOT), "start": self.started,
                   "end": stamp(), "phase_timeout_s": self.allowance,
                   "source_sha256": self.sources, "tool_versions": self.versions,
                   "children": self.children, "status": status, "detail": detail,
                   "repair_of": self.repair_of,
                   "acceptance_evidence": "/preparation/" not in str(self.output)}
        (self.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


def elaborate(execution):
    execution.run("default-elaboration",
                  ["iverilog", "-g2012", "-t", "null", "-s", "anvil_e1_top"] +
                  [str(p.relative_to(ROOT)) for p in sorted((ROOT / "rtl").glob("*.sv"))],
                  maximum=20)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", choices=("architecture", "behavior", "synthesis",
                                          "prepare-elaboration", "prepare-primitives",
                                          "prepare-forward", "prepare-integration",
                                          "prepare-scoreboard", "prepare-cost",
                                          "prepare-architecture", "prepare-synthesis",
                                          "prepare-profile-synthesis",
                                          "prepare-profile-simulation",
                                          "prepare-addresses", "prepare-packing"),
                        required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout-s", type=float, required=True)
    parser.add_argument("--seeds", default="17,89,203")
    parser.add_argument("--configs", default="A,B,C")
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    execution = Execution(args.output, args.timeout_s)
    execution.repair_of = args.repair_of
    try:
        execution.prerequisites(("python3", "yosys") if args.check in (
                                "synthesis", "prepare-synthesis", "prepare-profile-synthesis")
                                else ("python3", "iverilog", "vvp"))
        if args.check == "prepare-elaboration":
            elaborate(execution)
        elif args.check == "prepare-profile-synthesis":
            from profiling import profile_synthesis
            profile_synthesis(execution, args.configs.split(","))
        elif args.check == "prepare-profile-simulation":
            from profiling import profile_simulation
            profile_simulation(execution)
        elif args.check == "prepare-primitives":
            from primitives import verify_primitives
            verify_primitives(execution)
        elif args.check == "prepare-forward":
            from behavior import run_forward_probe
            run_forward_probe(execution)
        elif args.check == "prepare-integration":
            from behavior import run_integration_probe
            run_integration_probe(execution, args.configs.split(","),
                                  list(map(int, args.seeds.split(","))))
        elif args.check == "prepare-cost":
            from behavior import run_cost_probe
            run_cost_probe(execution)
        elif args.check == "prepare-addresses":
            from addresses import verify_addresses
            verify_addresses(execution)
        elif args.check == "prepare-packing":
            from packing import verify_packing
            verify_packing(execution)
        elif args.check == "prepare-scoreboard":
            from behavior import negative_control
            from model import CONFIGS
            original = ROOT / "evidence/preparation/verifier-forward-A17-20261014T2213"
            jobs = json.loads((original / "A-17.expected.json").read_text())
            negative_control(execution, original / "A-17-simulation.stdout.log",
                             jobs, CONFIGS["A"])
        elif args.check in ("architecture", "prepare-architecture"):
            from architecture import verify_architecture
            verify_architecture(execution)
        elif args.check == "behavior":
            from behavior import verify_behavior
            verify_behavior(execution, args.configs.split(","),
                            list(map(int, args.seeds.split(","))))
        else:
            from synthesis import verify_synthesis
            verify_synthesis(execution, args.configs.split(","),
                             probe=args.check=="prepare-synthesis")
        execution.remaining()
        execution.save("passed")
    except (AssertionError, RuntimeError, TimeoutError, OSError, ValueError,
            ImportError, KeyError) as error:
        execution.save("failed", f"{type(error).__name__}: {error}")
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: all implemented obligations for", args.check)
    return 0


if __name__ == "__main__":
    sys.exit(main())
