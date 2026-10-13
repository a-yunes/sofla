#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

live_tests=false
capture_screenshots=false
shortcut_tests=false
print_selection=false
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --live) live_tests=true ;;
        --screenshots) capture_screenshots=true ;;
        --shortcut) shortcut_tests=true ;;
        --print-selection) print_selection=true ;;
        *)
            echo "Usage: $0 [--live [--screenshots | --shortcut]] [--print-selection]" >&2
            exit 2
            ;;
    esac
    shift
done
if [[ "$capture_screenshots" == true && "$live_tests" == false ]]; then
    echo "--screenshots requires --live so its test-runner environment is explicit." >&2
    exit 2
fi

if [[ "$shortcut_tests" == true && "$live_tests" == false ]]; then
    echo "--shortcut requires --live." >&2
    exit 2
fi
if [[ "$shortcut_tests" == true && "$capture_screenshots" == true ]]; then
    echo "Run shortcut diagnostics separately from screenshot acceptance." >&2
    exit 2
fi
selection_arguments=()
if [[ "$shortcut_tests" == true ]]; then
    selection_arguments=(-only-testing:AppLauncherUITests/LauncherShortcutLiveAcceptanceTests)
elif [[ "$live_tests" == true ]]; then
    selection_arguments=(-skip-testing:AppLauncherUITests/LauncherShortcutLiveAcceptanceTests)
fi
if [[ "$print_selection" == true ]]; then
    if [[ "${#selection_arguments[@]}" -eq 0 ]]; then
        echo "Default isolated native and UI tests (live tests skip)."
    else
        printf '%s\n' "${selection_arguments[@]}"
    fi
    exit
fi

./scripts/check-toolchain.sh
os_version="$(sw_vers -productVersion)"
if [[ "${os_version%%.*}" -lt 26 ]]; then
    echo "UI tests require a logged-in macOS 26 or newer desktop session." >&2
    exit 1
fi

# Local signing is required for UI automation; choose a development team in Xcode if prompted.
common_arguments=(
    -quiet
    -project AppLauncher.xcodeproj
    -scheme AppLauncher
    -configuration Debug
    -destination 'platform=macOS,arch=arm64'
    -derivedDataPath build/DerivedData
    -parallel-testing-enabled NO
)
result_directory="build/TestResults"
mkdir -p "$result_directory"
result_stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"

if [[ "$live_tests" == false ]]; then
    result_bundle="$result_directory/AppLauncher-$result_stamp.xcresult"
    echo "Test result bundle: $result_bundle"
    xcodebuild "${common_arguments[@]}" -resultBundlePath "$result_bundle" test
    exit
fi

xcodebuild "${common_arguments[@]}" build-for-testing
shopt -s nullglob
base_xctestrun_candidates=(
    build/DerivedData/Build/Products/AppLauncher_macosx*-arm64.xctestrun
)
shopt -u nullglob
if [[ "${#base_xctestrun_candidates[@]}" -ne 1 ]]; then
    echo "Expected exactly one generated AppLauncher macOS arm64 test configuration." >&2
    printf 'Found: %s\n' "${base_xctestrun_candidates[@]:-none}" >&2
    exit 1
fi
base_xctestrun="${base_xctestrun_candidates[0]}"
live_xctestrun="build/DerivedData/Build/Products/AppLauncherLive.xctestrun"

/usr/bin/ditto "$base_xctestrun" "$live_xctestrun"
/usr/bin/plutil -insert AppLauncherUITests.EnvironmentVariables.APP_LAUNCHER_LIVE_TESTS \
    -string 1 "$live_xctestrun"
/usr/bin/plutil -insert AppLauncherUITests.TestingEnvironmentVariables.APP_LAUNCHER_LIVE_TESTS \
    -string 1 "$live_xctestrun"
if [[ "$capture_screenshots" == true ]]; then
    /usr/bin/plutil -insert AppLauncherUITests.EnvironmentVariables.APP_LAUNCHER_CAPTURE_SCREENSHOTS \
        -string 1 "$live_xctestrun"
    /usr/bin/plutil -insert AppLauncherUITests.TestingEnvironmentVariables.APP_LAUNCHER_CAPTURE_SCREENSHOTS \
        -string 1 "$live_xctestrun"
fi

result_bundle="$result_directory/AppLauncher-live-$result_stamp.xcresult"
echo "Live test result bundle: $result_bundle"
xcodebuild -quiet test-without-building -xctestrun "$live_xctestrun" \
    -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
    "${selection_arguments[@]}" \
    -resultBundlePath "$result_bundle"
