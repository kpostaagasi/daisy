#!/bin/zsh
# Builds Daisy.app from source into ./build
set -euo pipefail

cd "$(dirname "$0")"
swift build -c release

APP=build/Daisy.app
BIN=.build/release/Daisy

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat >"$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Daisy</string>
    <key>CFBundleIdentifier</key><string>io.daisy.Daisy</string>
    <key>CFBundleName</key><string>Daisy</string>
    <key>CFBundleDisplayName</key><string>Daisy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

cp "$BIN" "$APP/Contents/MacOS/Daisy"
codesign --force --sign - "$APP"

echo "Built $APP"
