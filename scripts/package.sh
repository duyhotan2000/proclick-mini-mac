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
# makehybrid writes the image without attaching a disk (hdiutil create needs one and often
# fails with "Resource busy"); convert then compresses it.
hdiutil makehybrid -hfs -hfs-volume-name "ProClick Mini" -o "$STAGE.raw.dmg" "$STAGE" >/dev/null
hdiutil convert "$STAGE.raw.dmg" -format UDZO -o "$DMG" >/dev/null
rm -f "$STAGE.raw.dmg"
IDENTITY="ProClick Mini Dev"
if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$DMG"
fi
echo "$PWD/$DMG"
