#!/usr/bin/env python3
"""Measure a local Release bundle and a hidden, synthetic 1,000-app session."""
import json
import pathlib
import statistics
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent


def cpu_seconds(value):
    parts = value.split(":")
    return sum(float(part) * 60 ** index for index, part in enumerate(reversed(parts)))


def sample(pid):
    values = subprocess.check_output(
        ["ps", "-p", str(pid), "-o", "rss=", "-o", "time="], text=True).split()
    if len(values) != 2:
        raise RuntimeError("Fixture process is unavailable")
    return int(values[0]) * 1024, cpu_seconds(values[1])


def main():
    app = ROOT / "build/Sofla.app"
    if not app.exists():
        raise SystemExit("Run ./scripts/build-app.sh first.")
    output = ROOT / "build/footprint.json"
    with tempfile.TemporaryDirectory(prefix="sofla-footprint-") as state:
        with tempfile.TemporaryFile() as log:
            process = subprocess.Popen([
                str(app / "Contents/MacOS/AppLauncher"), "--ui-testing", "--dense-ui-fixture",
                "--simulate-login-launch", "--state-directory", state,
            ], stdout=log, stderr=subprocess.STDOUT)
            try:
                time.sleep(15)
                initial_rss, initial_cpu = sample(process.pid)
                started = time.monotonic()
                resident = [initial_rss]
                for _ in range(20):
                    time.sleep(1)
                    rss, final_cpu = sample(process.pid)
                    resident.append(rss)
                elapsed = time.monotonic() - started
                report = {
                    "app_bytes": sum(p.lstat().st_size for p in app.rglob("*") if p.is_file() or p.is_symlink()),
                    "configuration": "Release, arm64",
                    "scope": "Hidden login-prewarmed fixture; 1,000 synthetic records, no live app scan or filesystem watcher. RSS is resident memory, not physical footprint.",
                    "settle_seconds": 15, "sample_seconds": elapsed, "samples": len(resident),
                    "rss_median_bytes": statistics.median(resident), "rss_peak_bytes": max(resident),
                    "idle_cpu_percent_one_core": max(0, final_cpu - initial_cpu) / elapsed * 100,
                }
                output.write_text(json.dumps(report, indent=2) + "\n")
                print(json.dumps(report, indent=2))
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
