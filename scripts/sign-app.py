#!/usr/bin/env python3
"""Prepare and sign Sofla and its nested updater helpers from the inside out."""
import argparse
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--identity", default="-")
    parser.add_argument("--prepare", action="store_true")
    args = parser.parse_args()
    framework = args.app / "Contents/Frameworks/Sparkle.framework"
    version = framework / "Versions/B"
    if not version.is_dir():
        raise ValueError("Sparkle is missing from the app")
    if args.prepare:
        # Sofla is not sandboxed, so Sparkle's sandbox-only XPC services are unnecessary.
        shutil.rmtree(version / "XPCServices", ignore_errors=True)
        (framework / "XPCServices").unlink(missing_ok=True)
        for binary in [version / "Sparkle", version / "Autoupdate",
                       version / "Updater.app/Contents/MacOS/Updater"]:
            architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
            if architectures != ["arm64"]:
                temporary = binary.with_suffix(".arm64")
                subprocess.run(["lipo", str(binary), "-thin", "arm64", "-output", str(temporary)], check=True)
                temporary.replace(binary)
            subprocess.run(["strip", "-S", str(binary)], check=True)
    common = ["codesign", "--force", "--options", "runtime", "--sign", args.identity]
    if args.identity != "-":
        common.append("--timestamp")
    for nested in [version / "Autoupdate", version / "Updater.app", framework]:
        subprocess.run([*common, str(nested)], check=True)
    entitlements = ROOT / "Configuration" / ("AdHoc.entitlements" if args.identity == "-" else "Distribution.entitlements")
    subprocess.run([*common, "--entitlements", str(entitlements), str(args.app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)


if __name__ == "__main__":
    main()
