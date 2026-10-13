#!/usr/bin/env python3
"""Run non-UI native regressions without the XCTest desktop control service (macOS 26+).

The hosted Xcode scheme remains authoritative for app lifecycle, shortcut, and UI acceptance.
This harness compiles the same source and tests, excluding only the app entry point/delegate.
Generated files and build products stay under the ignored build directory.
"""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
HARNESS = ROOT / "build" / "NativeRegressionHarness"
TEST_FILES = [
    "ApplicationIconCacheTests.swift", "CatalogLifecycleTests.swift",
    "ActivationHistoryTests.swift", "WallpaperServiceTests.swift",
    "TestSignal.swift", "LauncherModelIntegrationTests.swift",
    "LauncherSearchFieldTests.swift", "OnboardingTests.swift",
]
MANIFEST = '''// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "NativeRegressionHarness", platforms: [.macOS("26.0")],
    dependencies: [.package(name: "LauncherLibraries", path: "../..")],
    targets: [
        .target(name: "AppLauncher", dependencies: [
            .product(name: "LauncherCore", package: "LauncherLibraries"),
            .product(name: "LauncherInfrastructure", package: "LauncherLibraries")
        ], path: "AppLauncher", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "NativeRegressionTests", dependencies: ["AppLauncher",
            .product(name: "LauncherCore", package: "LauncherLibraries"),
            .product(name: "LauncherInfrastructure", package: "LauncherLibraries")
        ], path: "NativeTests")
    ], swiftLanguageModes: [.v6])
'''


def link(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink() and destination.resolve() != source.resolve():
        destination.unlink()
    if not destination.exists():
        destination.symlink_to(source)


def main():
    subprocess.run(["./scripts/check-toolchain.sh"], cwd=ROOT, check=True)
    version = subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip()
    if int(version.split(".")[0]) < 26:
        raise SystemExit("Native regressions require macOS 26 or newer.")
    HARNESS.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / "AppLauncher").rglob("*.swift"):
        if source.name not in {"AppLauncherApp.swift", "AppDelegate.swift", "AppDelegate+Menus.swift"}:
            link(source, HARNESS / "AppLauncher" / source.relative_to(ROOT / "AppLauncher"))
    for name in TEST_FILES:
        link(ROOT / "NativeTests" / name, HARNESS / "NativeTests" / name)
    for generated in HARNESS.rglob("*.swift"):
        if generated.is_symlink() and not generated.exists():
            generated.unlink()
    manifest = HARNESS / "Package.swift"
    if not manifest.exists() or manifest.read_text() != MANIFEST:
        manifest.write_text(MANIFEST)
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(HARNESS),
                    "-Xswiftc", "-warnings-as-errors"], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
