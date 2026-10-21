#!/bin/zsh
# Regenerates Resources/AppIcon.icns from Resources/AppIcon.svg
set -euo pipefail

cd "$(dirname "$0")"
SVG=Resources/AppIcon.svg
ICNS=Resources/AppIcon.icns
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/render.swift" <<'EOF'
import AppKit
let a = CommandLine.arguments
let image = NSImage(contentsOf: URL(fileURLWithPath: a[1]))!
let px = Int(a[3])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
EOF
swiftc -O "$WORK/render.swift" -o "$WORK/render"

SET="$WORK/AppIcon.iconset"
mkdir "$SET"
# No 16x16, 16@2x or 32x32 reps: macOS 26+ judges those small reps non-conforming
# and wraps the icon in a gray container; it downsamples the 64px rep instead.
"$WORK/render" "$SVG" "$SET/icon_32x32@2x.png" 64
for s in 128 256 512; do
    "$WORK/render" "$SVG" "$SET/icon_${s}x${s}.png" $s
    "$WORK/render" "$SVG" "$SET/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$SET" -o "$ICNS"

echo "Built $ICNS"
