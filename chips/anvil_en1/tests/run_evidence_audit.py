"""Audit retained preparation logs and current RTL identity, not acceptance."""

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from experiment import Experiment, ROOT, source_inputs


def project_path(name):
    path = Path(name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError("evidence paths must be project-relative")
    return ROOT / path


def inspect(receipts):
    records = []
    for name in receipts:
        path = project_path(name)
        if not Path(name).is_relative_to("evidence/preparation"):
            raise ValueError("only project preparation receipts may be audited")
        record = json.loads(path.read_text())
        if record["status"] not in ("passed", "failed") or not record.get("ended_at"):
            raise RuntimeError("preparation has not settled: " + name)
        hashes = record["source_sha256"]
        rtl = {name: digest for name, digest in hashes.items()
               if name.startswith(("rtl/", "anvil_e3_reference/rtl/"))}
        if not rtl:
            raise RuntimeError("missing RTL binding: " + name)
        for source, digest in rtl.items():
            if hashlib.sha256(project_path(source).read_bytes()).hexdigest() != digest:
                raise RuntimeError("RTL identity changed: " + source)
        logs = 0
        for command in record["commands"]:
            if (not command.get("ended_at") or
                    ("exit_code" not in command and not command.get("launch_error"))):
                raise RuntimeError("missing settled child outcome: " + name)
            for stream in ("stdout", "stderr"):
                if not project_path(command[stream]).is_file():
                    raise RuntimeError("raw preparation log is absent: " + command[stream])
                logs += 1
        records.append({
            "receipt": name, "status": record["status"], "rtl_files_matched": len(rtl),
            "raw_logs_present": logs,
            "receipt_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/evidence-audit")
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("receipts", nargs="+")
    args = parser.parse_args()
    if args.inspect:
        print(json.dumps(inspect(args.receipts), indent=2))
        return 0
    exp = Experiment(args.out, "verifier-preparation-retention-audit", source_inputs())
    error = None
    try:
        exp.run("python-version", [sys.executable, "--version"], 30)
        output = exp.run("audit", [
            sys.executable, "tests/run_evidence_audit.py", "--inspect", *args.receipts], 2400)
        exp.receipt["records"] = json.loads(output)
        exp.receipt["scope"] = (
            "Settled raw-log retention and current RTL identity only; failed experiments "
            "remain failed. Verification-source changes are not certified by this audit.")
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
