# Releasing Sofla

## Prepare

Run `./scripts/check.sh`, `./scripts/test-native-regressions.py`, and desktop UI checks.
Measure Release performance with `./scripts/benchmark.py --invocation` and
`./scripts/measure-footprint.py`. Set the version in `Configuration/Base.xcconfig`. Always increase `CURRENT_PROJECT_VERSION`.

The global-shortcut diagnostic needs event-posting access for its test runner.
If it skips, verify the physical shortcut manually. This permission is not required by Sofla.

## Package

```sh
./scripts/package-release.sh --unnotarized
```

This builds a styled, ad-hoc signed disk image without an Apple Developer subscription.
It generates a SHA-256 checksum, clean source ZIP, and `release.json` in `build/Installer`.
The manifest explicitly records that Apple has not notarized the build. Pass `--app path/to/Sofla.app`
to package a CI-tested bundle without recompiling it.
Packaging installs pinned build-only tools in `build/InstallerTools`. They write Finder settings
directly, without desktop automation. The final read-only image is remounted and its layout
validated. Open that finished image in Finder and inspect its appearance before release.

Use `--local` for a review-only disk image. Use `--release` for optional Developer ID signing
and notarization with `SOFLA_SIGNING_IDENTITY` and a `SOFLA_NOTARY_PROFILE` Keychain profile.
Never put credentials in the repository or remove quarantine from users' downloads.

## Verify

- Check the generated checksum, app signature, architecture, minimum OS, and source audit.
- Run `python3 scripts/runtime-smoke.py build/Sofla.app` on macOS 26 and the current macOS.
- Download the candidate in a browser on a clean Mac. Drag to Applications, attempt launch,
  and use Apple's app-specific Open Anyway flow. Finish setup and test the physical shortcut.
- Test optional Open at Login only with the tester's consent.

## Sign updates

```sh
python3 scripts/sparkle-tools.py
python3 scripts/update-feed.py
```

The `sofla-updates` key in login Keychain signs the archive and `appcast.xml`. Only the public
key belongs in `Configuration/Info.plist`. Back up the private key securely outside the repo;
losing it prevents signing updates for existing installations. Do not modify a signed feed.
Run `python3 scripts/test-updates.py` for real installation and tampering checks with temporary
app copies and an ephemeral test key. It never updates the installed Sofla app.

The app reads the latest release's `appcast.xml` on GitHub. Publish the archive and feed
together. Automatic checks and downloads are user choices in Settings > Updates.
Ad-hoc builds disable library validation to load Sparkle. Developer ID builds omit that exception.

## Publish

Create a draft release containing the versioned DMG, checksums, source ZIP, manifest, and signed `appcast.xml`.
Use the candidate notes in [CHANGELOG.md](CHANGELOG.md) and link [INSTALL.md](INSTALL.md).
Publish after installation acceptance, then set the website's download and checksum URLs.
Do not configure the public website to point at unpublished draft assets.

Keep a previous release for rollback. Never replace an already published version's assets.
Public source updates must come from the clean export, not private development history.
