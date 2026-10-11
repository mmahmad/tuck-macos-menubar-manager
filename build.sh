#!/bin/bash
# Builds build/Tuck.app as a universal (Apple Silicon + Intel) binary.
#   ./build.sh           build only
#   ./build.sh run       build and (re)launch from build/
#   ./build.sh install   build, copy to /Applications and launch
#   ./build.sh release   build an ad-hoc signed build/Tuck-<version>.zip for distribution
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
APP=build/Tuck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Tuck" "$APP/Contents/MacOS/Tuck"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# A stable signing identity keeps the Accessibility grant valid across rebuilds; ad-hoc signing does not.
# Release zips are ad-hoc signed so that no personal certificate is embedded in a public download.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
[ "${1:-}" = release ] && IDENTITY=
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

# Relaunching before the old instance has fully exited fails with LaunchServices error -600.
quit_running() {
    pkill -x Tuck 2>/dev/null || return 0
    while pgrep -x Tuck >/dev/null; do sleep 0.2; done
    sleep 0.5
}

case "${1:-}" in
    run)
        quit_running
        open "$APP" --args "${@:2}"
        ;;
    install)
        quit_running
        rm -rf /Applications/Tuck.app
        cp -R "$APP" /Applications/Tuck.app
        open /Applications/Tuck.app
        ;;
    release)
        VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
        ZIP="build/Tuck-$VERSION.zip"
        rm -f "$ZIP"
        ditto -c -k --keepParent "$APP" "$ZIP"
        echo "Packaged $ZIP"
        ;;
esac
