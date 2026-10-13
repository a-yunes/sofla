#!/usr/bin/env python3
"""Fetch the pinned release tooling used to sign Sofla updates."""
import hashlib
import pathlib
import subprocess
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = "2.10.0"
SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
DIRECTORY = ROOT / "build/SparkleTools"


def main():
    DIRECTORY.mkdir(parents=True, exist_ok=True)
    archive = DIRECTORY / "Sparkle.tar.xz"
    if not archive.exists():
        url = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz"
        with urllib.request.urlopen(url, timeout=60) as response:
            archive.write_bytes(response.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise ValueError("Sparkle tools archive checksum mismatch")
    subprocess.run(["tar", "-xf", str(archive), "-C", str(DIRECTORY)], check=True)
    print(f"Verified Sparkle {VERSION} release tools.")


if __name__ == "__main__":
    main()
