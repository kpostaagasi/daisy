#!/bin/zsh
# Builds Daisy.app and packages it as build/Daisy-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")"
./build.sh

APP=build/Daisy.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Daisy-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/Daisy.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Daisy $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --sign - "$DMG"

echo "Built $DMG"
