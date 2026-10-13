#!/usr/bin/env python3
"""Exercise Sparkle installation and signature rejection with disposable app copies."""
import functools
import hashlib
import http.server
import json
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "build/UpdateTests"
TOOLS = ROOT / "build/SparkleTools/bin"


def run(arguments, **kwargs):
    return subprocess.run([str(a) for a in arguments], check=True, **kwargs)


def build_driver(app):
    tool = WORK / "UpdaterCLI.app"
    (tool / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    (tool / "Contents/Frameworks").mkdir(exist_ok=True)
    pin = json.loads((ROOT / "AppLauncher.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())["pins"][0]
    revision = pin["state"]["revision"]
    source = WORK / "sources" / revision
    source.mkdir(parents=True, exist_ok=True)
    for name in ["main.m", "SPUCommandLineDriver.h", "SPUCommandLineDriver.m",
                 "SPUCommandLineUserDriver.h", "SPUCommandLineUserDriver.m"]:
        url = f"https://raw.githubusercontent.com/sparkle-project/Sparkle/{revision}/sparkle-cli/{name}"
        if not (source / name).exists():
            with urllib.request.urlopen(url, timeout=30) as response:
                (source / name).write_bytes(response.read())
    run(["xcrun", "clang", "-fobjc-arc", "-mmacosx-version-min=26.0",
         "-DSPU_OBJC_DIRECT_MEMBERS=", "-DSPU_OBJC_DIRECT=",
         "-F", TOOLS.parent, "-framework", "Sparkle", "-framework", "Cocoa",
         *[source / f for f in ["main.m", "SPUCommandLineDriver.m", "SPUCommandLineUserDriver.m"]],
         "-Wl,-rpath,@executable_path/../Frameworks", "-o", tool / "Contents/MacOS/sparkle"])
    info = {"CFBundleIdentifier": "app.sofla.updater-test.cli", "CFBundleName": "Sofla Update Test",
            "CFBundleExecutable": "sparkle", "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
            "LSUIElement": True, "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
    (tool / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    framework = tool / "Contents/Frameworks/Sparkle.framework"
    if framework.exists():
        shutil.rmtree(framework)
    run(["ditto", app / "Contents/Frameworks/Sparkle.framework", framework])
    run(["codesign", "--force", "--options", "runtime", "--entitlements",
         ROOT / "Configuration/AdHoc.entitlements", "--sign", "-", tool])
    return tool / "Contents/MacOS/sparkle"


def copy_app(source, target, identifier, version, public_key):
    run(["ditto", "--norsrc", "--noextattr", source, target])
    path = target / "Contents/Info.plist"
    info = plistlib.loads(path.read_bytes())
    info.update(CFBundleIdentifier=identifier, CFBundleVersion=str(version),
                SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUPublicEDKey=public_key)
    path.write_bytes(plistlib.dumps(info))
    run(["python3", ROOT / "scripts/sign-app.py", target])


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    app = ROOT / "build/Sofla.app"
    build = int(plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleVersion"])
    assert build > 1, "Use an incremented build number to test the prior build"
    if not (TOOLS / "generate_appcast").exists():
        run(["python3", ROOT / "scripts/sparkle-tools.py"])
    driver = build_driver(app)
    identifier = "app.sofla.updater-test." + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="sofla-update-test-") as folder:
        root = pathlib.Path(folder)
        private_key = root / "test-signing-key"
        public_key = subprocess.check_output(["xcrun", "swift", "-e", '''
import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: url, options: .atomic)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
print(key.publicKey.rawRepresentation.base64EncodedString())
''', str(private_key)], text=True).strip()
        feed = root / "valid"
        feed.mkdir()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=root))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}"
        try:
            new_app = root / "new/Sofla.app"
            copy_app(app, new_app, identifier, build, public_key)
            archive = feed / "Sofla-update.zip"
            run(["ditto", "-c", "-k", "--keepParent", new_app, archive])
            run([TOOLS / "generate_appcast", "--ed-key-file", private_key, "--maximum-deltas", "0",
                 "--download-url-prefix", url + "/valid/", feed])
            good_feed = (feed / "appcast.xml").read_bytes()
            bad_feed = root / "bad-feed"
            bad_feed.mkdir()
            (bad_feed / "appcast.xml").write_bytes(good_feed.replace(b"<title>", b"<title>Tampered ", 1))
            bad_archive = root / "bad-archive"
            bad_archive.mkdir()
            data = bytearray(archive.read_bytes())
            data[len(data) // 2] ^= 1
            (bad_archive / archive.name).write_bytes(data)
            (bad_archive / "appcast.xml").write_bytes(good_feed.replace(b"/valid/", b"/bad-archive/"))
            run([TOOLS / "sign_update", "--ed-key-file", private_key, bad_archive / "appcast.xml"])
            outcomes = {}
            old_app = root / "installed/Sofla.app"
            copy_app(app, old_app, identifier, build - 1, public_key)
            original = hashlib.sha256((old_app / "Contents/MacOS/AppLauncher").read_bytes()).hexdigest()
            saved_state = old_app.parent / "saved-layout.json"
            saved_state.write_text('{"folders":["Keep this layout"]}')
            preserved_state = saved_state.read_bytes()
            for scenario in ["unavailable", "bad-feed", "bad-archive", "valid"]:
                result = subprocess.run([str(driver), str(old_app), "--check-immediately",
                                         "--feed-url", url + f"/{scenario}/appcast.xml", "--verbose",
                                         "--user-agent-name", "SoflaUpdateTests"],
                                        capture_output=True, text=True, timeout=120)
                (WORK / f"{scenario}.log").write_text(result.stdout + result.stderr)
                after = plistlib.loads((old_app / "Contents/Info.plist").read_bytes())
                if scenario == "valid":
                    assert result.returncode == 0, result.stdout + result.stderr
                    assert after["CFBundleVersion"] == str(build), "Update was not installed"
                    run(["codesign", "--verify", "--deep", "--strict", old_app])
                else:
                    assert result.returncode != 0, "Tampered update was accepted"
                    assert after["CFBundleVersion"] == str(build - 1)
                    assert hashlib.sha256((old_app / "Contents/MacOS/AppLauncher").read_bytes()).hexdigest() == original
                    if scenario != "unavailable":
                        assert any(word in (result.stdout + result.stderr).lower() for word in ["signature", "improperly signed"]), result.stdout + result.stderr
                assert saved_state.read_bytes() == preserved_state, "User data outside the app was changed"
                outcomes[scenario] = {"passed": True, "exitCode": result.returncode}
                # Sparkle tears down its separate installer after the client exits on a rejected archive.
                # A new client must not race that installer session while it is still cleaning up.
                deadline = time.monotonic() + 15
                while True:
                    processes = subprocess.check_output(["ps", "-axo", "command="], text=True)
                    pending = [line for line in processes.splitlines() if "Autoupdate" in line and str(root) in line]
                    if not pending:
                        break
                    if time.monotonic() >= deadline:
                        raise RuntimeError("The disposable installer did not finish cleanup")
                    time.sleep(0.25)
            (WORK / "results.json").write_text(json.dumps(outcomes, indent=2) + "\n")
            print("Passed: signed installation, failed-request recovery, tampering rejection, and preserved data.")
        finally:
            server.shutdown()
            server.server_close()
            # Only this disposable test identity, never Sofla's real preferences.
            subprocess.run(["defaults", "delete", identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
