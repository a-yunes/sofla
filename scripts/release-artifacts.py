#!/usr/bin/env python3
"""Validate a packaged app and write portable release metadata and checksums."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent


def validate_metadata(info, architectures, binary_minimum):
    if info.get("CFBundleIdentifier") != "app.sofla.launcher":
        raise ValueError("Unexpected app identity")
    if info.get("CFBundleExecutable") != "AppLauncher":
        raise ValueError("Unexpected executable")
    version = info.get("CFBundleShortVersionString", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", version):
        raise ValueError("Invalid release version")
    if info.get("LSMinimumSystemVersion") != "26.0" or binary_minimum != "26.0":
        raise ValueError("Both the app and executable must target macOS 26.0")
    if architectures != ["arm64"]:
        raise ValueError("Expected an Apple silicon app")
    return version


def file_record(path):
    return {
        "name": path.name,
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["local", "unnotarized", "release"])
    parser.add_argument("disk_image", type=pathlib.Path)
    parser.add_argument("app", type=pathlib.Path)
    args = parser.parse_args()
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    updater_configuration = plistlib.loads((ROOT / "Configuration/Info.plist").read_bytes())
    for key in ["SUPublicEDKey", "SUFeedURL", "SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableSystemProfiling"]:
        if info.get(key) != updater_configuration[key]:
            raise ValueError(f"Packaged updater configuration differs: {key}")
    if not (args.app / "Contents/Resources/LICENSE.sparkle").is_file():
        raise ValueError("Sparkle's bundled license is missing")
    binary = args.app / "Contents/MacOS/AppLauncher"
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    load_commands = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
    minimum = re.search(r"\bminos\s+([0-9.]+)", load_commands)
    version = validate_metadata(info, architectures, minimum.group(1) if minimum else None)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
    signature = subprocess.run(["codesign", "-d", "--verbose=4", str(args.app)],
                               capture_output=True, text=True, check=True).stderr
    ad_hoc = "Signature=adhoc" in signature
    if ad_hoc != (args.mode != "release"):
        raise ValueError("Signature does not match the selected distribution mode")
    destination = args.disk_image.parent
    source = destination / f"Sofla-{version}-source.zip"
    shutil.copyfile(ROOT / "build/Sofla-source.zip", source)
    guide = destination / "INSTALL.md"
    shutil.copyfile(ROOT / "INSTALL.md", guide)
    manifest = destination / "release.json"
    manifest.write_text(json.dumps({
        "schemaVersion": 1,
        "version": version,
        "build": info["CFBundleVersion"],
        "minimumSystemVersion": info["LSMinimumSystemVersion"],
        "architecture": "arm64",
        "codeSigning": "ad-hoc" if ad_hoc else "Developer ID",
        "notarized": args.mode == "release",
        "distributionMode": args.mode,
        "updates": {"feedURL": info["SUFeedURL"], "signedFeed": True,
                    "publicKey": info["SUPublicEDKey"]},
        "installedBytes": sum(p.lstat().st_size for p in args.app.rglob("*") if p.is_file() or p.is_symlink()),
        "artifacts": {"diskImage": file_record(args.disk_image), "source": file_record(source)},
        "installationGuide": guide.name,
    }, indent=2) + "\n")
    record = file_record(args.disk_image)
    args.disk_image.with_suffix(".dmg.sha256").write_text(f"{record['sha256']}  {record['name']}\n")
    checksums = "".join(f"{file_record(p)['sha256']}  {p.name}\n"
                        for p in [args.disk_image, source, guide, manifest])
    (destination / "SHA256SUMS").write_text(checksums)
    print(f"Validated {version}, arm64, macOS 26.0; notarized={args.mode == 'release'}")


if __name__ == "__main__":
    main()
