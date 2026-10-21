#!/bin/zsh
# Builds Daisy.app from source into ./build
set -euo pipefail

cd "$(dirname "$0")"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"

APP=build/Daisy.app
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Daisy"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

cp "$BIN" "$APP/Contents/MacOS/Daisy"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP"
