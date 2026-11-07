#!/bin/bash
# Builds "build/ProClick Mini.app", signed with "ProClick Mini Dev" when set up (see
# setup-signing.sh), otherwise ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ProClickMini
BIN="$(swift build -c release --product ProClickMini --show-bin-path)/ProClickMini"

APP="build/ProClick Mini.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ProClickMini"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="ProClick Mini Dev"
if ! security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "warning: \"$IDENTITY\" not found; signing ad hoc (permissions reset on every build)" >&2
    IDENTITY="-"
fi
codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "$PWD/$APP"
