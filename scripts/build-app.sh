#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/check-toolchain.sh

# Ad-hoc signing preserves code integrity. Public unnotarized builds need first-launch approval.
xcodebuild -quiet -project AppLauncher.xcodeproj -scheme AppLauncher \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build/ReleaseDerivedData ARCHS=arm64 \
    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_CODE_COVERAGE=NO build

rm -rf build/Sofla.app
/usr/bin/ditto --norsrc --noextattr build/ReleaseDerivedData/Build/Products/Release/Sofla.app \
    build/Sofla.app
cp LICENSE build/Sofla.app/Contents/Resources/LICENSE
cp LICENSE.sparkle build/Sofla.app/Contents/Resources/LICENSE.sparkle
# Remove build-machine paths in debug symbols before signing the deliverable.
/usr/bin/strip -S build/Sofla.app/Contents/MacOS/AppLauncher
python3 scripts/sign-app.py build/Sofla.app --prepare
python3 scripts/audit-source.py --app build/Sofla.app
/usr/bin/codesign --verify --deep --strict build/Sofla.app
echo "Ad-hoc signed Release app: $(pwd)/build/Sofla.app"
