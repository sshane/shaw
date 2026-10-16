#!/bin/bash
# Builds Shaw.app into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app ] && ! xcode-select -p | grep -q Xcode; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
swift build -c "$CONFIG"
APP=build/Shaw.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Shaw" "$APP/Contents/MacOS/Shaw"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
