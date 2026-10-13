#!/bin/bash
set -euo pipefail

# Xcode itself checks license/first-launch readiness. Never accept a license here.
xcode_version="$(xcodebuild -version | awk '/^Xcode / { print $2 }')"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"

if [[ "${xcode_version%%.*}" -lt 27 || "${sdk_version%%.*}" -lt 27 ]]; then
    echo "Xcode 27 or newer with the macOS 27 SDK is required." >&2
    exit 1
fi

echo "Xcode $xcode_version; macOS SDK $sdk_version"
xcrun swift --version
