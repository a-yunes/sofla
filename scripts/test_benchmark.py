import importlib.util
import json
import os
import pathlib
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location("benchmark", pathlib.Path(__file__).with_name("benchmark.py"))
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class BenchmarkValidationTests(unittest.TestCase):
    def test_short_or_invalid_sample_sets_cannot_pass_a_budget(self):
        for samples in ([1], [1, float("nan")], [1, float("inf")], [1, -1], [1, "2"]):
            with self.subTest(samples=samples), self.assertRaises(ValueError):
                benchmark.validated_samples(samples, 2)

    def test_tail_outlier_is_included_in_p95(self):
        summary = benchmark.validated_samples([1] * 18 + [120, 130], 20)
        self.assertEqual(summary["p50_ms"], 1)
        self.assertEqual(summary["p95_ms"], 120)

    def test_missing_stale_or_malformed_results_cannot_be_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "result.json"
            started = time.time()
            with self.assertRaises(FileNotFoundError):
                benchmark.read_fresh(path, started)
            path.write_text('{"value": 1}')
            os.utime(path, (started - 60, started - 60))
            with self.assertRaises(ValueError):
                benchmark.read_fresh(path, started)
            path.write_text("malformed")
            with self.assertRaises(json.JSONDecodeError):
                benchmark.read_fresh(path, started)
            path.write_text('{"value": 2}')
            self.assertEqual(benchmark.read_fresh(path, started), {"value": 2})


if __name__ == "__main__":
    unittest.main()
