#!/usr/bin/env python3
"""Calibrated Release checks. --invocation presents an isolated fixture launcher on the desktop."""
import argparse
import datetime
import json
import math
import pathlib
import platform
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent


def command(*args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs).strip()


def percentile(samples, fraction):
    return sorted(samples)[max(0, math.ceil(len(samples) * fraction) - 1)]


def validated_samples(samples, count):
    if len(samples) != count or any(
        not isinstance(x, (int, float)) or not math.isfinite(x) or x < 0 for x in samples
    ):
        raise ValueError(f"Expected {count} finite, nonnegative timing samples")
    return {"count": count, "p50_ms": percentile(samples, .5), "p95_ms": percentile(samples, .95)}


def read_fresh(path, started):
    if path.stat().st_mtime < started - 1:
        raise ValueError(f"Stale benchmark result: {path}")
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--invocation", action="store_true", help="also build and measure native warm focus")
    args = parser.parse_args()
    subprocess.run(["./scripts/check-toolchain.sh"], cwd=ROOT, check=True)
    directory = ROOT / "build" / "Benchmarks"
    directory.mkdir(parents=True, exist_ok=True)
    output = pathlib.Path(tempfile.mkdtemp(prefix="run-", dir=directory))
    try:
        revision = command("git", "rev-parse", "HEAD", stderr=subprocess.DEVNULL)
        dirty = bool(command("git", "status", "--porcelain", stderr=subprocess.DEVNULL))
    except subprocess.CalledProcessError:
        revision, dirty = "source-export", None
    metadata = {
        "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "revision": revision,
        "dirty": dirty,
        "hardware": command("sysctl", "-n", "hw.model"),
        "cpu": command("sysctl", "-n", "machdep.cpu.brand_string"),
        "architecture": platform.machine(),
        "os": command("sw_vers", "-productVersion"),
        "swift": command("xcrun", "swift", "--version"),
        "configuration": "Release",
        "limits": {"search_p95_ms": 16, "warm_invocation_p95_ms": 100, "search_view_update_p95_ms": 16},
        "scope": "Search computation, optional native visible/focused invocation and native search-field update acknowledgement; excludes GPU presentation and target-app startup.",
    }
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Results: {output}", flush=True)
    subprocess.run(["xcrun", "swift", "build", "-c", "release", "--product", "LauncherBenchmarks",
                    "-Xswiftc", "-warnings-as-errors"], cwd=ROOT, check=True)
    binary = pathlib.Path(command("xcrun", "swift", "build", "-c", "release", "--show-bin-path"))
    started = time.time()
    subprocess.run([str(binary / "LauncherBenchmarks"), str(output / "search.json")],
                   cwd=ROOT, check=True, timeout=180)
    search = read_fresh(output / "search.json", started)
    if search["recordCount"] != 1000 or search["warmupCount"] != 100:
        raise ValueError("Unexpected search benchmark workload")
    scenarios = search["scenarios"]
    if len(scenarios) != 4 or {s["name"] for s in scenarios} != {"exact", "prefix", "broad", "fuzzy-miss"}:
        raise ValueError("Incomplete search scenarios")
    summary = {}
    for scenario in scenarios:
        summary[scenario["name"]] = validated_samples(scenario["samplesMilliseconds"], 1000)
    if next(s for s in scenarios if s["name"] == "broad")["resultCount"] != 1000:
        raise ValueError("Broad search did not exercise all records")
    if args.invocation:
        subprocess.run(["./scripts/build-app.sh"], cwd=ROOT, check=True)
        started = time.time()
        with tempfile.TemporaryDirectory(prefix="launcher-benchmark-state-") as state:
            with (output / "invocation.log").open("w") as log:
                subprocess.run([
                    "/usr/bin/open", "-n", "-W", "--stdout", str(output / "invocation.log"),
                    "--stderr", str(output / "invocation.log"), str(ROOT / "build/Sofla.app"), "--args",
                    "--ui-testing", "--dense-ui-fixture", "--state-directory", state,
                    "--measure-invocation", "--benchmark-invocation", "--benchmark-output",
                    str(output / "invocation.json"),
                ], cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        try:
            invocation = read_fresh(output / "invocation.json", started)
            summary["warm-invocation"] = validated_samples(invocation["warmSamplesMilliseconds"], 20)
            if invocation["searchRecordCount"] != 1000:
                raise ValueError("Native search benchmark requires 1,000 fixture records")
            summary["search-view-update"] = validated_samples(invocation["searchUpdateSamplesMilliseconds"], 100)
        except (OSError, ValueError) as error:
            diagnostic = next((line for line in (output / "invocation.log").read_text().splitlines()
                               if line.startswith("invocation_benchmark_error=")), str(error))
            (output / "summary.json").write_text(json.dumps({
                "metrics": summary, "invocation_error": diagnostic,
            }, indent=2) + "\n")
            raise SystemExit(f"Invocation benchmark failed: {diagnostic}. See {output / 'invocation.log'}")
    failures = [name for name, result in summary.items()
                if result["p95_ms"] >= (100 if name == "warm-invocation" else 16)]
    (output / "summary.json").write_text(json.dumps({"metrics": summary, "failed_budgets": failures}, indent=2) + "\n")
    for name, values in summary.items():
        print(f"{name}: p50={values['p50_ms']:.3f} ms, p95={values['p95_ms']:.3f} ms")
    if failures:
        raise SystemExit("Performance budget exceeded: " + ", ".join(failures))


if __name__ == "__main__":
    main()
