#!/usr/bin/env python3
"""Generate and verify a signed GitHub-hosted update feed for a packaged release."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def verify_item(feed, manifest):
    root = ET.parse(feed).getroot()
    items = root.findall("channel/item")
    if len(items) != 1:
        raise ValueError("Expected exactly one release in the update feed")
    item = items[0]
    enclosure = item.find("enclosure")
    version = manifest["version"]
    image = manifest["artifacts"]["diskImage"]
    expected_url = f"https://github.com/a-yunes/sofla/releases/download/v{version}/{image['name']}"
    if enclosure is None or enclosure.get("url") != expected_url:
        raise ValueError("Update feed points at an unexpected download")
    if enclosure.get("length") != str(image["bytes"]) or not enclosure.get(f"{{{SPARKLE}}}edSignature"):
        raise ValueError("Update archive signature or length is missing")
    if item.findtext(f"{{{SPARKLE}}}version") != manifest["build"]:
        raise ValueError("Update build number does not match the app")
    if item.findtext(f"{{{SPARKLE}}}minimumSystemVersion") != "26.0":
        raise ValueError("Update minimum macOS does not match the app")
    return enclosure.get(f"{{{SPARKLE}}}edSignature")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=pathlib.Path, nargs="?", default=ROOT / "build/Installer")
    args = parser.parse_args()
    directory = args.directory.resolve()
    manifest = json.loads((directory / "release.json").read_text())
    if manifest["distributionMode"] == "local":
        raise ValueError("Do not publish a local review installer")
    tools = ROOT / "build/SparkleTools/bin"
    if not (tools / "generate_appcast").exists():
        subprocess.run(["python3", str(ROOT / "scripts/sparkle-tools.py")], check=True)
    account = "sofla-updates"
    public_key = subprocess.check_output([str(tools / "generate_keys"), "--account", account, "-p"], text=True).strip()
    configured_key = plistlib.loads((ROOT / "Configuration/Info.plist").read_bytes())["SUPublicEDKey"]
    if public_key != configured_key:
        raise ValueError("Keychain signing key does not match Sofla's embedded public key")
    with tempfile.TemporaryDirectory(prefix="update-feed-", dir=ROOT / "build") as temporary:
        staging = pathlib.Path(temporary)
        image = directory / manifest["artifacts"]["diskImage"]["name"]
        if hashlib.sha256(image.read_bytes()).hexdigest() != manifest["artifacts"]["diskImage"]["sha256"]:
            raise ValueError("Packaged image no longer matches release metadata")
        shutil.copyfile(image, staging / image.name)
        subprocess.run([str(tools / "generate_appcast"), "--account", account,
                        "--maximum-deltas", "0", "--download-url-prefix",
                        f"https://github.com/a-yunes/sofla/releases/download/v{manifest['version']}/",
                        "--link", "https://sofla.app", str(staging)], env=os.environ | {"TZ": "UTC"}, check=True)
        feed = staging / "appcast.xml"
        signature = verify_item(feed, manifest)
        subprocess.run([str(tools / "sign_update"), "--account", account, "--verify", str(feed)], check=True)
        subprocess.run([str(tools / "sign_update"), "--account", account, "--verify", str(image), signature], check=True)
        shutil.copyfile(feed, directory / "appcast.xml")
    # Include the signed feed in the same portable checksum list as the other release files.
    checksum = hashlib.sha256((directory / "appcast.xml").read_bytes()).hexdigest()
    sums = directory / "SHA256SUMS"
    lines = [line for line in sums.read_text().splitlines() if not line.endswith("  appcast.xml")]
    sums.write_text("\n".join([*lines, f"{checksum}  appcast.xml"]) + "\n")
    print("Signed update feed and archive verified against Sofla's update key.")


if __name__ == "__main__":
    main()
