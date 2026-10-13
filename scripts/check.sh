#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/check-toolchain.sh
python3 scripts/audit-source.py
python3 -B -m unittest discover -s scripts -p 'test_*.py'
xcrun swift-format lint --strict --recursive Package.swift AppLauncher Sources Tests UITests NativeTests
xcrun swift test --enable-code-coverage -Xswiftc -warnings-as-errors
xcodebuild -quiet -project AppLauncher.xcodeproj -scheme AppLauncher \
    -configuration Debug -destination 'generic/platform=macOS' \
    -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build-for-testing
echo "Native launcher and test-bundle compilation passed."
