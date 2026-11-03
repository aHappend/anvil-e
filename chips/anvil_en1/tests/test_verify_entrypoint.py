"""Entrypoint lifecycle unit tests; synthetic commands are not RTL evidence."""

import sys

sys.dont_write_bytecode = True

import argparse
import contextlib
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import experiment
import verify


WORK = None


class EntrypointTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(dir=WORK, prefix="case-"))
        (self.root / "tests").mkdir()
        self.source = self.root / "tests/input.py"
        self.source.write_text("VALUE = 17\n")
        self.sources = {"tests/input.py": hashlib.sha256(self.source.read_bytes()).hexdigest()}
        self.addCleanup(patch.stopall)
        patch.object(experiment, "ROOT", self.root).start()
        patch.object(verify, "ROOT", self.root).start()
        patch.object(verify, "source_inputs", return_value=[self.source]).start()

    def new_experiment(self, prefix="evidence/probe"):
        return experiment.Experiment(prefix, "synthetic-entrypoint-unit", [self.source])

    def test_six_suites_and_frozen_seeds(self):
        self.assertEqual(len(verify.SUITES), 6)
        for suite in verify.SUITES:
            plan = verify.steps(suite)
            self.assertEqual(len({step.name for step in plan}), len(plan))
            for step in plan:
                self.assertTrue(step.script.endswith(".py"))
                self.assertNotIn("--fixtures-from", step.arguments)
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                verify.main(["--suite", "behavior", "--out", "evidence/a", "--seeds", "17"])
        self.assertEqual(caught.exception.code, 2)

    def test_retry_retains_failure_and_allocates_fresh_children(self):
        first = self.new_experiment("evidence/retry/run")
        with self.assertRaisesRegex(RuntimeError, "exited 7"):
            first.run("negative", [sys.executable, "-B", "-c",
                                   "import sys; print('intentional'); sys.exit(7)"])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(first.finish("intentional unit failure"), 1)
        retained = (first.out / "receipt.json").read_bytes()
        second = self.new_experiment("evidence/retry/run")
        self.assertNotEqual(first.out, second.out)
        self.assertEqual((first.out / "receipt.json").read_bytes(), retained)
        self.assertEqual(first.receipt["commands"][0]["exit_code"], 7)
        (self.root / "regular-file").write_text("preserve")
        with self.assertRaises(FileExistsError):
            verify.main(["--suite", "contract", "--out", "regular-file"])
        self.assertEqual((self.root / "regular-file").read_text(), "preserve")

    def test_cwd_and_no_bytecode_are_inherited(self):
        run = self.new_experiment()
        nested = self.root / "copy"
        nested.mkdir()
        (nested / "sibling.py").write_text("VALUE = 43\n")
        output = run.run(
            "imports", [sys.executable, "-c",
                        "import sys; from pathlib import Path; "
                        "sys.path.insert(0, str(Path.cwd())); import sibling; "
                        "assert sys.dont_write_bytecode; assert sibling.VALUE == 43; "
                        "print(Path.cwd().name)"], cwd=nested)
        self.assertEqual(output.strip(), "copy")
        self.assertEqual(run.receipt["commands"][0]["cwd"], "copy")
        self.assertFalse((nested / "__pycache__").exists())
        with self.assertRaisesRegex(ValueError, "already retained"):
            run.run("imports", [sys.executable, "--version"])

    def test_interrupted_child_receipt_is_retained_without_rewrite(self):
        run = self.new_experiment()
        nested = run.out / "child-12345678" / "receipt.json"
        script = (
            "from pathlib import Path; import time; "
            f"path=Path({str(nested)!r}); path.parent.mkdir(); "
            "path.write_text('{\"status\":\"running\",\"commands\":[]}\\n'); "
            "time.sleep(60)")
        with self.assertRaisesRegex(TimeoutError, "recorded timeout"):
            run.run("interrupted", [sys.executable, "-c", script], timeout=1)
        raw = nested.read_bytes()
        retained = run.receipt["interrupted_children"]
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0]["path"], str(nested.relative_to(self.root)))
        self.assertEqual(retained[0]["sha256"], hashlib.sha256(raw).hexdigest())
        self.assertTrue(retained[0]["retained_without_rewrite"])
        self.assertEqual(json.loads(raw)["status"], "running")
        command = run.receipt["commands"][0]
        self.assertTrue(command["timed_out"])
        self.assertIsNotNone(command["exit_code"])
        self.assertIn("ended_at", command)

    def test_guard_precedes_fresh_process_sibling_imports(self):
        run = self.new_experiment()
        entry = self.root / "tests/verify.py"
        entry.write_bytes(Path(verify.__file__).read_bytes())
        sibling = self.root / "tests/experiment.py"
        sibling.write_text(
            "import sys\nfrom pathlib import Path\n"
            "assert sys.dont_write_bytecode, 'guard did not precede sibling import'\n"
            "ROOT = Path(__file__).resolve().parents[1]\n"
            "class Experiment: pass\n"
            "def source_inputs(): return []\n")
        output = run.run("fresh-import", [
            "env", "-u", "PYTHONDONTWRITEBYTECODE", sys.executable,
            "tests/verify.py", "--help"])
        self.assertIn("--suite", output)
        self.assertFalse((self.root / "tests/__pycache__").exists())

    def test_exit_zero_does_not_hide_missing_coverage(self):
        for suite in ("behavior", "defects", "benchmark"):
            with self.subTest(suite=suite), self.assertRaisesRegex(
                    RuntimeError, "required completed comparison cells absent"):
                verify.close_coverage(suite, [{"status": "passed", "exit_code": 0}], verify.SEEDS)
        row = {"kind": "comparison", "model": 1, "comparisons": 3,
               "completed": True, "mismatches": 0}
        self.assertEqual(verify.require_cases(
            [{"observations": [row]}], [(1,)], ("model",), "comparison"), 1)
        for field, value in (("comparisons", 0), ("completed", False), ("mismatches", 1)):
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                verify.require_cases([{"observations": [{**row, field: value}]}],
                                     [(1,)], ("model",), "comparison")

    def test_false_child_success_and_missing_logs_are_rejected(self):
        run = self.new_experiment()
        run.run("python", [sys.executable, "--version"])
        with contextlib.redirect_stdout(io.StringIO()):
            run.finish()
        message = json.dumps({"status": "passed", "receipt": str(run.relative / "receipt.json")})
        _, receipt = verify.parse_result(message, self.root)
        verify.require_child_sources(receipt, self.sources)
        fixtures = self.root / "validation-fixtures"
        fixtures.mkdir()
        receipt["commands"][0]["exit_code"] = 19
        invalid_exit = fixtures / "synthetic-bad-exit.json"
        invalid_exit.write_text(json.dumps(receipt))
        message = json.dumps({"status": "passed",
                              "receipt": str(invalid_exit.relative_to(self.root))})
        with self.assertRaisesRegex(RuntimeError, "unsuccessful tool"):
            verify.parse_result(message, self.root)
        receipt["commands"][0]["exit_code"] = 0
        receipt["commands"][0]["stdout"] = "missing-log.txt"
        invalid_log = fixtures / "synthetic-missing-log.json"
        invalid_log.write_text(json.dumps(receipt))
        message = json.dumps({"status": "passed",
                              "receipt": str(invalid_log.relative_to(self.root))})
        with self.assertRaisesRegex(RuntimeError, "raw log"):
            verify.parse_result(message, self.root)
        with self.assertRaisesRegex(RuntimeError, "non-project-relative"):
            verify.parse_result(json.dumps({"receipt": "../old/receipt.json"}), self.root)
        with self.assertRaisesRegex(RuntimeError, "source binding"):
            verify.require_child_sources(
                {"source_sha256": {"tests/input.py": "different"}}, self.sources)

    def test_outer_command_failure_finishes_nonzero_receipt(self):
        patch.object(verify, "TOOLS", {**verify.TOOLS, "contract": ("missing-unit-tool",)}).start()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = verify.main(["--suite", "contract", "--out", "evidence/outer"])
        self.assertEqual(code, 1)
        result = json.loads(output.getvalue().strip().splitlines()[-1])
        receipt = json.loads((self.root / result["receipt"]).read_text())
        self.assertEqual(receipt["status"], "failed")
        self.assertEqual(receipt["exit_code"], 1)
        self.assertIn("launch_error", receipt["commands"][0])
        self.assertEqual(len(list((self.root / "evidence/outer").glob("run-*"))), 1)

    def test_mutation_records_require_the_intended_runtime_failure(self):
        run = self.new_experiment()
        for label in ("control-compile", "control-simulate", "mutant-compile"):
            run.run(label, [sys.executable, "-c", "print('synthetic control')"])
        run.run("mutant-simulate", [
            sys.executable, "-c", "import sys; print('EXPECTED_ASSERTION'); sys.exit(1)"],
            expected_exit_codes=(1,))
        clean = ("control-compile", "control-simulate")
        mutant = ("mutant-compile", "mutant-simulate")
        with self.assertRaisesRegex(RuntimeError, "intended assertion"):
            run.record_rejection("synthetic", "WRONG_ASSERTION", clean, mutant)
        self.assertNotIn("observations", run.receipt)
        run.record_rejection("synthetic", "EXPECTED_ASSERTION", clean, mutant)
        self.assertTrue(run.receipt["observations"][0]["rejected_by_intended_assertion"])
        self.assertEqual(len(run.receipt["observations"]), 1)


def main():
    global WORK
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/entrypoint-lifecycle")
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--work")
    parser.add_argument("--repair-of")
    parser.add_argument("--rtl-smoke", action="store_true")
    args = parser.parse_args()
    if args.worker:
        WORK = Path(args.work)
        WORK.mkdir()
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(EntrypointTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        if result.wasSuccessful():
            print(f"SUMMARY entrypoint_lifecycle tests={result.testsRun} rtl_claims=0")
        return int(not result.wasSuccessful())
    exp = experiment.Experiment(args.out, "entrypoint-lifecycle-diagnostic",
                                experiment.source_inputs(), args.repair_of)
    error = None
    try:
        exp.run("python-version", [sys.executable, "--version"], 30)
        output = exp.run(
            "unit-tests", [sys.executable, "-B", "tests/test_verify_entrypoint.py",
                           "--worker", "--work", str(exp.relative / "unit-work")])
        if "SUMMARY entrypoint_lifecycle tests=9 rtl_claims=0" not in output:
            raise RuntimeError("entrypoint unit comparisons did not complete")
        exp.receipt["unit_tests"] = 9
        exp.receipt["scope"] = "Synthetic entrypoint lifecycle only; no RTL simulation or synthesis"
        if args.rtl_smoke:
            exp.receipt["children"] = []
            receipt = verify.execute_step(
                exp, verify.Step("csr-dispatch", "run_csr.py",
                                 ("--defect", "--simulator", "verilator")))
            if not receipt["mutant_rejected"]:
                raise RuntimeError("real CSR mutation was not rejected by the dispatched child")
            observations = receipt.get("observations", [])
            if (len(observations) != 1
                    or observations[0]["defect"] != "csr-clear-priority"
                    or observations[0]["rejected_by_intended_assertion"] is not True):
                raise RuntimeError("real CSR rejection did not propagate into the coverage ledger")
            exp.receipt["scope"] = (
                "Entrypoint lifecycle and real public CSR/mutation dispatch; "
                "not a complete L1 suite or neural inference")
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
