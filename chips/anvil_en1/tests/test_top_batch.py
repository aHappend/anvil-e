"""Synthetic checker tests, not DUT numerical or throughput evidence."""

import sys

sys.dont_write_bytecode = True

import unittest
import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_top_batch import compare
from run_baseline import compare_traffic
from run_top_matrix import traffic_observations
from run_replay_history import compare as compare_history
from coverage_matrix import CAPACITIES, batch_cells, fixture_keys, top_cells
from verify import close_coverage, steps
import text_cases
from experiment import Experiment, source_inputs


class BatchComparisonTests(unittest.TestCase):
    def setUp(self):
        self.expected = {"logits": [1.0] * 32}
        self.output = "".join(f"LOGIT {i} 16256\n" for i in range(32))
        self.summary = ("SUMMARY top logits=32 cycles=100 reads=20 weight_bytes=64 "
                        "input_bytes=16 kv_bytes=0 tokens=17\n")

    def test_completed_comparisons_and_traffic_conservation(self):
        counts, error = compare(self.output + self.summary, self.expected, 17)
        self.assertEqual(counts["reads"], 20)
        self.assertEqual(error, 0)

    def test_incomplete_and_duplicate_completion(self):
        for output in (self.output, self.summary,
                       self.output + self.summary + self.summary,
                       self.output.replace("LOGIT 31 16256\n", "") + self.summary):
            with self.subTest(output=output[-100:]), self.assertRaises(RuntimeError):
                compare(output, self.expected, 17)

    def test_order_nonfinite_and_numerical_defects(self):
        for defect in ("LOGIT 30 16256\n", "LOGIT 31 32640\n", "LOGIT 31 16880\n"):
            output = self.output.replace("LOGIT 31 16256\n", defect) + self.summary
            with self.subTest(defect=defect), self.assertRaises(RuntimeError):
                compare(output, self.expected, 17)

    def test_spill_empty_denominator_and_wrong_context(self):
        for before, after in (("kv_bytes=0", "kv_bytes=4"),
                              ("weight_bytes=64", "weight_bytes=60"),
                              ("reads=20", "reads=0"),
                              ("tokens=17", "tokens=16")):
            with self.subTest(after=after), self.assertRaises(RuntimeError):
                compare(self.output + self.summary.replace(before, after), self.expected, 17)

    def test_reference_shape_and_finiteness(self):
        for values in ([1.0] * 31, [1.0] * 33, [float("nan")] * 32):
            with self.subTest(length=len(values)), self.assertRaises(ValueError):
                compare(self.output + self.summary, {"logits": values}, 17)


class SharedFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path.cwd(), prefix="manifest-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.addCleanup(patch.stopall)
        patch.object(text_cases, "ROOT", self.root).start()
        for name in text_cases.REFERENCE_SOURCES:
            path = self.root / name
            path.parent.mkdir(exist_ok=True)
            path.write_text("synthetic checker source\n")
        image = self.root / "checkpoint-images" / "fixture.bin"
        image.parent.mkdir()
        image.write_bytes(b"synthetic checker image")
        expected = self.root / "expected.json"
        expected.write_text(json.dumps({"logits": [1.0] * 32}))
        self.manifest = {
            "schema": 1,
            "reference_source_sha256": {
                name: text_cases.digest(self.root / name)
                for name in text_cases.REFERENCE_SOURCES},
            "cases": [{
                "name": "m1-p0-s17-n1", "model": 1, "precision": 0, "seed": 17,
                "tokens": 1, "image": "checkpoint-images/fixture.bin",
                "image_sha256": text_cases.digest(image), "expected": "expected.json",
                "expected_sha256": text_cases.digest(expected),
            }],
        }

    def load(self):
        path = self.root / "text-cases.json"
        path.write_text(json.dumps(self.manifest))
        return text_cases.load(path, (1,), (0,), (17,), (1,))

    def test_selected_fixture_hashes_and_reference_are_loaded(self):
        cases = self.load()
        self.assertEqual(len(cases), 1)
        self.assertEqual(cases[0]["reference"]["logits"], [1.0] * 32)
        self.assertEqual(cases[0]["image_sha256"], hashlib.sha256(
            b"synthetic checker image").hexdigest())

    def test_stale_reference_and_payload_are_rejected(self):
        source = self.root / text_cases.REFERENCE_SOURCES[0]
        source.write_text("changed source\n")
        with self.assertRaisesRegex(RuntimeError, "source binding"):
            self.load()
        source.write_text("synthetic checker source\n")
        for name in ("checkpoint-images/fixture.bin", "expected.json"):
            path = self.root / name
            original = path.read_bytes()
            path.write_bytes(b"corrupted")
            with self.assertRaisesRegex(RuntimeError, "hash differs"):
                self.load()
            path.write_bytes(original)

    def test_duplicate_missing_and_escaping_cells_are_rejected(self):
        self.manifest["cases"].append(dict(self.manifest["cases"][0]))
        with self.assertRaisesRegex(RuntimeError, "duplicate"):
            self.load()
        self.manifest["cases"].pop()
        self.manifest["cases"][0]["tokens"] = 16
        with self.assertRaises(KeyError):
            self.load()
        self.manifest["cases"][0]["tokens"] = 1
        self.manifest["cases"][0]["image"] = "../outside.bin"
        with self.assertRaisesRegex(ValueError, "project-relative"):
            self.load()


class BaselineTrafficTests(unittest.TestCase):
    def setUp(self):
        self.cases = [["cell", 1, 17, 64, 16, "commands.txt"]]
        self.metadata = {"cell": {"precision": 1, "seed": 43}}
        self.output = (
            "CASE cell write_bytes=64 read_bytes=16 responses=20 sources=4\n"
            "SUMMARY baseline cases=1 write_bytes=64 read_bytes=16 "
            "responses=20 owner_pairs=4\n")

    def test_completed_actual_traffic_is_retained(self):
        records = compare_traffic(self.output, self.cases, self.metadata)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["accepted_external_kv_bytes"], 80)
        self.assertEqual(records[0]["comparisons"], 4)
        self.assertEqual(records[0]["precision"], 1)
        self.assertTrue(records[0]["completed"])

    def test_missing_duplicate_zero_and_inconsistent_traffic_are_rejected(self):
        for output in (
                "", self.output.splitlines()[1],
                self.output + self.output.splitlines()[0] + "\n",
                self.output.replace("sources=4", "sources=0"),
                self.output.replace("responses=20", "responses=19", 1),
                self.output.replace("write_bytes=64", "write_bytes=60", 1),
                self.output.replace("owner_pairs=4", "owner_pairs=5")):
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                compare_traffic(output, self.cases, self.metadata)
        with self.assertRaises(RuntimeError):
            compare_traffic("SUMMARY baseline cases=0 write_bytes=0 read_bytes=0 "
                            "responses=0 owner_pairs=0\n", [], {})


class RepresentativeDispatchTests(unittest.TestCase):
    def test_cells_cover_named_axes_without_cartesian_claim(self):
        cells = top_cells()
        self.assertEqual(len(cells), 20)
        self.assertEqual(len({cell.key for cell in cells}), 20)
        for model in (1, 2):
            for precision in (0, 1):
                group = [cell for cell in cells if
                         cell.model == model and cell.precision == precision]
                self.assertEqual({cell.tokens for cell in group if not cell.fallback}, {1, 16, 17})
                self.assertEqual({cell.tokens for cell in group if cell.fallback}, {1, 17})
                self.assertEqual({cell.seed for cell in group}, {17, 43, 89})
                self.assertEqual({cell.capacity for cell in group}, {1, 3, 64})
        self.assertEqual({cell.fixture_key for cell in cells}, set(fixture_keys()))
        self.assertEqual(
            {(cell.tokens, cell.capacity) for cell in cells if not cell.fallback},
            {(n, c) for n in (1, 16, 17) for c in CAPACITIES})
        grouped = [cell for fallback in (0, 1) for capacity in CAPACITIES
                   for cell in batch_cells(capacity, fallback)]
        self.assertEqual(set(grouped), set(cells))
        self.assertEqual(len(grouped), len(cells))

    def test_behavior_dispatch_uses_one_shared_reference_matrix(self):
        plan = steps("behavior")
        self.assertEqual([step.script for step in plan].count("run_top_matrix.py"), 1)
        self.assertFalse(any(step.script == "run_top_smoke.py" for step in plan))
        self.assertFalse(any(step.script == "run_baseline.py" for step in plan))
        self.assertIn("run_replay_history.py", [step.script for step in plan])
        production = next(step for step in plan if step.script == "run_owner_production.py")
        self.assertIn("--compact", production.arguments)

    def test_numerical_pass_does_not_invent_integrated_allocations(self):
        records = [{"observations": [
            {"kind": "top-numerical", **cell.__dict__, "comparisons": 32,
             "completed": True, "mismatches": 0} for cell in top_cells()]}]
        with self.assertRaisesRegex(RuntimeError, "top-integration-allocation-traffic"):
            close_coverage("behavior", records, (17, 43, 89))


class SharedTrafficTests(unittest.TestCase):
    def setUp(self):
        cell = top_cells()[0]
        self.baseline = [{
            "kind": "matched-unshared-public-traffic",
            **{name: getattr(cell, name) for name in ("model", "precision", "seed", "tokens")},
            "comparisons": 168, "accepted_external_kv_bytes": 6048,
            "completed": True, "mismatches": 0,
        }]
        self.candidate = [{
            "kind": "top-numerical", **cell.__dict__, "comparisons": 32,
            "completed": True, "mismatches": 0,
            "public_counts": {"reads": 20, "weight_bytes": 64, "input_bytes": 16,
                              "kv_bytes": 0},
        }]

    def test_complete_real_denominator_is_required(self):
        records = traffic_observations(self.candidate, self.baseline)
        self.assertEqual(records[0]["matched_unshared_external_kv_bytes"], 6048)
        self.assertEqual(records[0]["accepted_external_kv_bytes"], 0)
        self.assertEqual(records[0]["total_external_bytes"], 80)
        self.assertEqual(records[0]["kind"], "candidate-public-kv-traffic")

    def test_missing_empty_duplicate_and_incomplete_denominators_are_rejected(self):
        for baseline in ([], self.baseline * 2,
                         [{**self.baseline[0], "accepted_external_kv_bytes": 0}],
                         [{**self.baseline[0], "completed": False}],
                         [{**self.baseline[0], "comparisons": 0}]):
            with self.subTest(baseline=baseline), self.assertRaises((KeyError, RuntimeError)):
                traffic_observations(self.candidate, baseline)

    def test_traffic_and_numerical_failure_are_not_relabelled(self):
        for field, value in (("completed", False), ("mismatches", 1), ("comparisons", 0)):
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                traffic_observations([{**self.candidate[0], field: value}], self.baseline)
        for counts in ({"kv_bytes": -4}, {"kv_bytes": 2722}, {"reads": 19}):
            record = {**self.candidate[0], "public_counts":
                      {**self.candidate[0]["public_counts"], **counts}}
            with self.subTest(counts=counts), self.assertRaises(RuntimeError):
                traffic_observations([record], self.baseline)
        with self.assertRaises(RuntimeError):
            traffic_observations([], self.baseline)


class ReplayHistoryCheckerTests(unittest.TestCase):
    def setUp(self):
        self.expected = list(range(8))
        self.output = "".join(f"HIDDEN {i} {i}\n" for i in range(8))
        self.summary = (
            "SUMMARY history components=8 cycles=100 history=8 input0=4 input1=4 "
            "weight_bytes=64 requests=24 responses=24 metadata=8 grants=4 depth=3 "
            "backing_requests=16 backing_responses=16 backing_written_words=8 "
            "live=512 shadow=8192 memo_hits=1 evictions=0 reprojections=4 "
            "local=1 global=1 stalls=5 kv_bytes=0\n")

    def test_completed_history_requires_real_public_events(self):
        counts = compare_history(self.output + self.summary, self.expected, True)
        self.assertEqual(counts["depth"], 3)
        self.assertEqual(counts["history"], 8)

    def test_wrong_vector_missing_response_and_missing_history_are_rejected(self):
        for before, after in (("HIDDEN 7 7", "HIDDEN 7 8"), ("history=8", "history=0"),
                              ("responses=24", "responses=23"), ("input0=4", "input0=0"),
                              ("global=1", "global=0"), ("depth=3", "depth=1"),
                              ("shadow=8192", "shadow=1048577")):
            with self.subTest(after=after), self.assertRaises(RuntimeError):
                compare_history((self.output + self.summary).replace(before, after),
                                self.expected, True)
        for output in (self.output, self.summary, self.output + self.summary * 2):
            with self.assertRaises(RuntimeError):
                compare_history(output, self.expected, True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="evidence/preparation/top-batch-checker")
    parser.add_argument("--repair-of")
    parser.add_argument("--worker", action="store_true")
    args = parser.parse_args()
    if args.worker:
        suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        if result.wasSuccessful():
            print(f"SUMMARY batch_checker tests={result.testsRun} rtl_claims=0")
        return int(not result.wasSuccessful())
    exp = Experiment(args.out, "verifier-batch-checker", source_inputs(), args.repair_of)
    error = None
    try:
        exp.run("python-version", [sys.executable, "--version"], 30)
        output = exp.run("unit-tests", [
            sys.executable, "-B", "tests/test_top_batch.py", "--worker"])
        if "SUMMARY batch_checker tests=18 rtl_claims=0" not in output:
            raise RuntimeError("batch checker comparisons did not complete")
        exp.receipt["unit_tests"] = 18
    except (OSError, RuntimeError, TimeoutError, ValueError, KeyError) as exc:
        error = exc
    return exp.finish(error)


if __name__ == "__main__":
    raise SystemExit(main())
