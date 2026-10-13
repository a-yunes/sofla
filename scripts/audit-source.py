#!/usr/bin/env python3
"""Audit the public source allowlist. Optionally export a clean, metadata-free ZIP."""
import argparse
import hashlib
import os
import pathlib
import re
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIRECTORIES = {"AppLauncher", "AppLauncher.xcodeproj", "Configuration", "Sources", "Tests",
               "NativeTests", "UITests", "scripts", "plans", "docs", ".github"}
ROOT_FILES = {"Package.swift", "README.md", "AGENTS.md", "design.md", "CONTRIBUTING.md", "SECURITY.md",
              "NOTICE.md", "LICENSE", "LICENSE.sparkle", "RELEASING.md", "INSTALL.md", "CHANGELOG.md", ".gitignore", ".gitattributes", ".swift-format"}
EXTENSIONS = {".swift", ".py", ".sh", ".md", ".yml", ".yaml", ".json", ".pbxproj",
              ".xcscheme", ".xcconfig", ".png", ".svg", ".icns", ".plist", ".entitlements",
              ".resolved", ".xcworkspacedata"}
# Explicitly approved public attribution. Emails and other identifiers remain private.
PUBLIC_CREDITS = {b"aleksei iunes"}
SKIP = {"xcuserdata", "__pycache__", ".DS_Store", "Local.xcconfig"}
PATTERNS = {
    "home path": re.compile(rb"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
    "email address": re.compile(rb"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"),
    "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "credential": re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})"),
}


def source_files(root=ROOT):
    for entry in sorted(root.iterdir()):
        if entry.name in ROOT_FILES:
            if entry.is_symlink():
                raise ValueError(f"Source symlink: {entry.name}")
            yield entry
        elif entry.name in DIRECTORIES:
            for directory, dirs, files in os.walk(entry, followlinks=False):
                for name in dirs + files:
                    path = pathlib.Path(directory, name)
                    if path.is_symlink():
                        raise ValueError(f"Source symlink: {path.relative_to(root)}")
                dirs[:] = sorted(d for d in dirs if d not in SKIP)
                for name in sorted(files):
                    if name in SKIP:
                        continue
                    path = pathlib.Path(directory, name)
                    if path.suffix not in EXTENSIONS:
                        raise ValueError(f"Unreviewed source file: {path.relative_to(root)}")
                    yield path


def audit(files, root=ROOT):
    failures = []
    # Local author identifiers are checked without recording them in source or logs.
    try:
        authors = subprocess.check_output(
            ["git", "log", "--all", "--format=%an%n%ae"], cwd=root,
            stderr=subprocess.DEVNULL).splitlines()
    except subprocess.CalledProcessError:
        authors = []
    identifiers = {a.lower() for a in authors if len(a) > 4 and b"bot" not in a.lower()
                   and b"sofla" not in a.lower() and a.lower() not in PUBLIC_CREDITS}
    for path in files:
        data = path.read_bytes().replace(b"\0", b"")
        label = str(path.relative_to(root))
        # Preserve upstream license attribution. Only the exact reviewed license may contain its public email.
        upstream_license = path.name == "LICENSE.sparkle" and hashlib.sha256(path.read_bytes()).hexdigest() == "389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe"
        for category, pattern in PATTERNS.items():
            if category == "email address" and upstream_license:
                continue
            if any(not (category == "email address" and re.fullmatch(rb"icon_\d+x\d+@2x\.png", match.group()))
                   for match in pattern.finditer(data)):
                failures.append(f"{label}: {category}")
        if any(value in data.lower() for value in identifiers):
            failures.append(f"{label}: local author identifier")
        if path.suffix == ".md" and "\u2014".encode() in data:
            failures.append(f"{label}: em dash in documentation")
    return failures


def export(files, output, root=ROOT):
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            info = zipfile.ZipInfo("sofla/" + str(path.relative_to(root)), (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (0o100755 if path.stat().st_mode & 0o111 else 0o100644) << 16
            archive.writestr(info, path.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export", type=pathlib.Path)
    parser.add_argument("--app", type=pathlib.Path)
    args = parser.parse_args()
    files = list(source_files())
    failures = audit(files)
    if failures:
        raise SystemExit("Source audit failed:\n" + "\n".join(failures))
    print(f"Source audit passed: {len(files)} files. Git history and local metadata are excluded.")
    if args.app:
        app = args.app.resolve()
        failures = audit([p for p in app.rglob("*") if p.is_file()], root=app)
        if failures:
            raise SystemExit("Artifact audit failed:\n" + "\n".join(failures))
        print("App artifact privacy audit passed.")
    if args.export:
        export(files, args.export.resolve())
        print("Clean source archive created.")


if __name__ == "__main__":
    main()
