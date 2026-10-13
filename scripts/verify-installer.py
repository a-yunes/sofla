#!/usr/bin/env python3
"""Verify the saved layout and contents of a mounted, finished Sofla disk image."""
import argparse
import pathlib
import re


def require_contents(root):
    layout = root / ".DS_Store"
    if not layout.is_file() or layout.stat().st_size < 32:
        raise ValueError("Finder layout was not saved: missing or empty .DS_Store")
    if layout.read_bytes()[4:8] != b"Bud1":
        raise ValueError("Invalid Finder layout file")
    if not (root / ".background.png").is_file():
        raise ValueError("Installer background is missing")
    if not (root / "Applications").is_symlink() or (root / "Applications").resolve() != pathlib.Path("/Applications"):
        raise ValueError("Applications link is missing or incorrect")
    if not (root / "Sofla.app/Contents/Info.plist").is_file():
        raise ValueError("Sofla app is missing")


def verify_layout(records):
    options = records["."]["icvp"]
    if options.get("backgroundType") != 2 or b".background.png" not in options.get("backgroundImageAlias", b""):
        raise ValueError("Installer background reference was not saved")
    if options.get("iconSize") != 88 or options.get("textSize") != 14 or options.get("arrangeBy") != "none":
        raise ValueError("Installer icon layout was not saved")
    window = records["."]["bwsp"]
    if window.get("ShowToolbar") or window.get("ShowSidebar") or window.get("ShowStatusBar"):
        raise ValueError("Installer window chrome was not saved")
    if list(map(int, re.findall(r"-?\d+", window["WindowBounds"])[-2:])) != [660, 440]:
        raise ValueError("Installer window size was not saved")
    if records["Sofla.app"]["Iloc"] != (180, 220) or records["Applications"]["Iloc"] != (480, 220):
        raise ValueError("Installer icon positions were not saved")


def main():
    from ds_store import DSStore

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mount", type=pathlib.Path)
    args = parser.parse_args()
    require_contents(args.mount)
    with DSStore.open(str(args.mount / ".DS_Store"), "r") as records:
        verify_layout(records)
    print("Final installer layout verified.")


if __name__ == "__main__":
    main()
