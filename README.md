# Daisy

Daisy is an open-source, fully unlocked, configurable alternative to the
Mac App Store utility **Tangerine** (v2.0.2, `com.th.Tangerine`): a
menu-bar drop panel that converts, previews and strips files by dragging
them onto a blooming "fan" of conversion targets.

No paywall, no usage counting, no purchase service — everything is free.

## Status (v0.1.0)

| Tangerine feature | Daisy | Notes |
| --- | --- | --- |
| Floating drop panel (menu-bar, glass) | ✅ `FanPanelView` | NSPanel + `NSVisualEffectView` hud material |
| Fan of conversion targets | ✅ 11 petals | expand on drag-enter |
| WebP conversion | ✅ | `cwebp` |
| JPEG / PNG / HEIC conversion | ✅ | CoreGraphics + ImageIO (no external tools) |
| MP4 / MP3 / WAV conversion | ✅ | `ffmpeg` |
| GIF conversion | ✅ | `ffmpeg` (12 fps, scaled to 640px) |
| Strip metadata | ✅ | `exiftool -all=` |
| Copy file to clipboard | ✅ | `NSPasteboard` |
| Reveal in Finder | ✅ | `NSWorkspace` |
| Settings window (tool paths, output folder, timeout) | ✅ | overrides Homebrew auto-detection |
| Free uses + one-time purchase (RevenueCat) | ❌ removed | open-source alternative |
| Welcome window, login item | 🚧 roadmap | |
| Hover-drag detection while dragging from other apps | 🚧 | current: drop/hub staging |
| Photo annotation | 🚧 roadmap | |
| Video trim / bleep / redaction | 🚧 roadmap | |
| QR code decode | 🚧 roadmap | |
| Documents (EPUB/DOCX/Pages) → PDF | 🚧 roadmap | |
| Fan highlight sound | 🚧 roadmap | |

## Build

```bash
./build.sh          # swift build + assemble build/Daisy.app + ad-hoc sign
open build/Daisy.app
```

Requires Xcode and macOS 13+.

## Tools Daisy uses (not bundled)

Daisy refuses to redistribute GPL binaries. Install once:

```bash
brew install ffmpeg webp exiftool
```

Daisy auto-detects `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`;
override each path in Settings.

## Architecture

```
Sources/Daisy/
  main.swift               entry, accessory activation policy
  AppDelegate.swift        wires menu bar + panel + settings
  AppSettings.swift        UserDefaults-backed settings
  ConversionTarget.swift   fan petals (WebP…Reveal)
  ConversionEngine.swift   dispatches each conversion
  ToolRunner.swift         external process runner (timeout, captured output)
  ToolLocator.swift        Homebrew auto-detection
  FanView.swift            glass panel + petals + drag-and-drop routing
  FloatingDropPanel.swift  NSPanel lifecycle + task status
  MenuBarController.swift  status item, folder conversion, settings, quit
  SettingsWindow.swift     settings UI
```

## How Tangerine was mapped

The upstream app was analyzed statically (Mach-O arm64, unstripped Swift
symbols: 39 Tangerine classes — `MenuBarController`, `FloatingFileWindowController`,
`ConversionOverlayController`, `FanCenterLabelView`, `FormatDropTarget`,
`UsageCountStore` family, `PaywallModel`, `RevenueCatPurchaseService`…).
Daisy re-implements the feature surface from scratch; no Tangerine code,
assets or design tokens are reused, and the paywall stack (RevenueCat,
usage stores, welcome/paywall windows) is deliberately absent.

## License

MIT — see `LICENSE`.
