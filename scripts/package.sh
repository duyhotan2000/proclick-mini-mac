#!/bin/bash
# Builds the app and wraps it in a drag-to-install disk image:
# build/ProClickMini-<version>.dmg containing "ProClick Mini.app" and an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh >/dev/null
APP="build/ProClick Mini.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/ProClickMini-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
# hdiutil intermittently fails with "Resource busy" while macOS indexes the fresh copy; retry.
for attempt in 1 2 3 4 5; do
    if hdiutil create -volname "ProClick Mini" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet "$DMG"; then
        break
    fi
    [ "$attempt" = 5 ] && { echo "error: hdiutil create kept failing" >&2; exit 1; }
    sleep 2
done
IDENTITY="ProClick Mini Dev"
if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$DMG"
fi
echo "$PWD/$DMG"
