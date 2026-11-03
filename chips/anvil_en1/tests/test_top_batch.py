"""Synthetic checker tests, not DUT numerical or throughput evidence."""

import sys

sys.dont_write_bytecode = True

import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_top_batch import compare


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


if __name__ == "__main__":
    unittest.main(verbosity=2)
