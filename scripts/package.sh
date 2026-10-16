#!/bin/bash
# Builds a self-contained, universal (Apple Silicon + Intel) Shaw.app and zips it for sharing.
# Output: build/Shaw.zip
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app ] && ! xcode-select -p | grep -q Xcode; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
swift build -c release --arch arm64 --arch x86_64
BIN=.build/out/Products/Release/Shaw
[ -f "$BIN" ] || BIN=.build/apple/Products/Release/Shaw
STAGE=build/package
APP="$STAGE/Shaw.app"
rm -rf "$STAGE" build/Shaw.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shaw"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
cat > "$STAGE/How to open Shaw.txt" <<'TXT'
Shaw — a music app (macOS 14 Sonoma or newer, Apple Silicon or Intel)

1. Drag Shaw.app into your Applications folder.
2. Double-click it. macOS will say it can't verify the developer
   (it isn't from the App Store) — click Done.
3. Open System Settings → Privacy & Security, scroll down, and click
   "Open Anyway" next to the message about Shaw. Confirm with your password.

You only have to do this once. Everything Shaw needs is inside the app.
TXT
ditto -c -k --keepParent "$APP" build/Shaw.zip
(cd "$STAGE" && zip -q ../Shaw.zip "How to open Shaw.txt")
echo "Created build/Shaw.zip ($(du -h build/Shaw.zip | cut -f1))"
