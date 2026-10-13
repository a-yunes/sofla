#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:---local}"
if [[ "$#" -gt 0 ]]; then shift; fi
app_source=""
if [[ "$#" -eq 2 && "$1" == "--app" ]]; then
    app_source="$2"
    shift 2
fi
if [[ "$#" -ne 0 || ( "$mode" != "--local" && "$mode" != "--unnotarized" && "$mode" != "--release" ) ]]; then
    echo "Usage: $0 [--local | --unnotarized | --release] [--app path/to/Sofla.app]" >&2
    exit 2
fi
if [[ "$mode" == "--release" ]]; then
    : "${SOFLA_SIGNING_IDENTITY:?Set a Developer ID Application identity}"
    : "${SOFLA_NOTARY_PROFILE:?Set a notarytool Keychain profile}"
    [[ "$SOFLA_SIGNING_IDENTITY" == "Developer ID Application:"* ]] || exit 2
fi

if [[ -z "$app_source" ]]; then
    ./scripts/build-app.sh
    app_source="$PWD/build/Sofla.app"
fi
codesign --verify --deep --strict "$app_source"
python3 scripts/audit-source.py --app "$app_source"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_source/Contents/Info.plist")" != "app.sofla.launcher" ]]; then
    echo "Expected the Sofla app bundle." >&2
    exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_source/Contents/Info.plist")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Invalid release version: $version" >&2
    exit 1
fi
python3 scripts/audit-source.py --export build/Sofla-source.zip
mkdir -p build/Installer
work="$(mktemp -d "$PWD/build/Installer/staging.XXXXXX")"
# Keep Finder bookmarks free of home paths and leave any user-mounted installer alone.
mount="/Volumes/Sofla-Installer-$$"
if [[ -e "$mount" ]]; then
    echo "Temporary installer mount point already exists; retry packaging." >&2
    rm -rf "$work"
    exit 1
fi
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then hdiutil detach "$mount" -quiet || true; fi
    rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/content/.background"
ditto --norsrc --noextattr "$app_source" "$work/content/Sofla.app"
cp LICENSE "$work/content/Sofla.app/Contents/Resources/LICENSE"
cp LICENSE.sparkle "$work/content/Sofla.app/Contents/Resources/LICENSE.sparkle"
ln -s /Applications "$work/content/Applications"
if [[ "$mode" == "--release" ]]; then
    xcrun swift scripts/installer-background.swift "$work/content/.background/install.png"
else
    xcrun swift scripts/installer-background.swift "$work/content/.background/install.png" --unnotarized
fi

if [[ "$mode" == "--release" ]]; then
    python3 scripts/sign-app.py "$work/content/Sofla.app" --identity "$SOFLA_SIGNING_IDENTITY"
    ditto -c -k --keepParent "$work/content/Sofla.app" "$work/notarize.zip"
    xcrun notarytool submit "$work/notarize.zip" --keychain-profile "$SOFLA_NOTARY_PROFILE" --wait
    xcrun stapler staple "$work/content/Sofla.app"
    xcrun stapler validate "$work/content/Sofla.app"
    spctl --assess --type execute "$work/content/Sofla.app"
    output="$PWD/build/Installer/Sofla-$version-arm64.dmg"
else
    python3 scripts/sign-app.py "$work/content/Sofla.app"
    if [[ "$mode" == "--unnotarized" ]]; then
        output="$PWD/build/Installer/Sofla-$version-arm64.dmg"
    else
        output="$PWD/build/Installer/Sofla-local-$$.dmg"
    fi
fi
codesign --verify --deep --strict "$work/content/Sofla.app"
# Build tools live outside the app and write Finder metadata directly.
python3 -m venv build/InstallerTools
build/InstallerTools/bin/python -m pip install --quiet --disable-pip-version-check \
    dmgbuild==1.6.7 ds_store==1.3.3 mac_alias==2.2.3
build/InstallerTools/bin/python scripts/build-installer.py \
    "$work/content/Sofla.app" "$work/content/.background/install.png" "$output" "$version"
hdiutil verify "$output"
# Validate the delivered image, not only the writable staging volume.
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mount" "$output"
mounted=true
build/InstallerTools/bin/python scripts/verify-installer.py "$mount"
codesign --verify --deep --strict "$mount/Sofla.app"
python3 scripts/audit-source.py --app "$mount/Sofla.app"
hdiutil detach -quiet "$mount"
mounted=false
if [[ "$mode" == "--release" ]]; then
    codesign --timestamp --sign "$SOFLA_SIGNING_IDENTITY" "$output"
    xcrun notarytool submit "$output" --keychain-profile "$SOFLA_NOTARY_PROFILE" --wait
    xcrun stapler staple "$output"
    xcrun stapler validate "$output"
    spctl --assess --type open --context context:primary-signature "$output"
fi
python3 scripts/release-artifacts.py "${mode#--}" "$output" "$work/content/Sofla.app"
echo "Installer: $output ($mode)"
