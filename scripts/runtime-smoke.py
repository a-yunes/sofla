#!/usr/bin/env python3
"""Run the packaged native UI with disposable fixtures, without enforcing host-dependent timings."""
import argparse
import json
import pathlib
import platform
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--require-os-major", type=int)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("build/runtime-smoke.json"))
    args = parser.parse_args()
    os_version = subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip()
    if args.require_os_major and int(os_version.split(".")[0]) != args.require_os_major:
        raise SystemExit("Unexpected host OS; refusing to claim compatibility coverage.")
    app = args.app.resolve()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    log = args.output.with_suffix(".log").resolve()
    with tempfile.TemporaryDirectory(prefix="sofla-runtime-") as directory:
        result = pathlib.Path(directory) / "result.json"
        state = pathlib.Path(directory) / "state"
        started = time.time()
        subprocess.run([
            "open", "-n", "-W", "--stdout", str(log), "--stderr", str(log), str(app), "--args",
            "--ui-testing", "--state-directory", str(state), "--measure-invocation",
            "--benchmark-invocation", "--benchmark-output", str(result),
        ], check=True, timeout=180)
        if not result.exists() or result.stat().st_mtime < started:
            raise SystemExit(f"Native runtime did not finish its UI journey. Inspect {log.name}.")
        report = json.loads(result.read_text())
        if report["searchRecordCount"] != 1000 or len(report["warmSamplesMilliseconds"]) != 20 \
                or len(report["searchUpdateSamplesMilliseconds"]) != 100:
            raise SystemExit("Incomplete native UI journey.")
    args.output.write_text(json.dumps({
        "os": os_version, "architecture": platform.machine(), "passed": True,
        "warmInvocations": 20, "searchUpdates": 100,
        "scope": "Packaged app startup and native UI updates using synthetic records. Not a Gatekeeper or physical-shortcut test.",
    }, indent=2) + "\n")
    print(f"Packaged native runtime smoke passed on macOS {os_version} ({platform.machine()}).")


if __name__ == "__main__":
    main()
