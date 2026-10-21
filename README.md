<p align="center"><img src="Resources/AppIcon.svg" width="128" alt="Daisy icon"></p>

# Daisy

Daisy is an open-source, fully unlocked, configurable alternative to the
Mac App Store utility **Tangerine** (v2.0.2, `com.th.Tangerine`): a
menu-bar drop panel that converts, previews and strips files by dragging
them onto a blooming "fan" of conversion targets.

No paywall, no usage counting, no purchase service — everything is free.

## Status (v0.2.2)

| Tangerine feature | Daisy | Notes |
| --- | --- | --- |
| Global drag shortcut detector (`DragGestureMonitor`) | ✅ `DragGestureMonitor` | Polls drag pasteboard + `⌥` / `⌘` / `⌃` modifiers at 60Hz while dragging |
| 3 Radial Fan Modes (`Conversions`, `Tools`, `Actions`) | ✅ `ConversionFanMode` | Context-aware petals filtered by dragged file types |
| Annular sector petals (`FormatDropTarget`) | ✅ `FanView.swift` | 372×372 overlay at cursor, Glass & Metallic themes, center hub |
| Fan feedback | ✅ `FanHaptics` | Silent; trackpad haptics for petal hover, mode switch, fan open and drop |
| Floating File Shelf ("Float" & Paperclip tab) | ✅ `FloatingFileWindowController` | Edge-snapping collapsible shelf, QuickLook thumbnails, drag-out |
| Operation progress HUD (`OrangeIndeterminateProgressView`) | ✅ `OperationProgressWindowController` | Floating glass progress bar + Finder reveal on completion |
| Image, Audio, Video, Document, Subtitle, Archive conversions | ✅ `ConversionEngine` | 35+ formats (`WebP`, `PNG`, `JPG`, `HEIC`, `PDF`, `DOCX`, `MP4`, `GIF`, `MP3`, `WAV`, `SRT`, `VTT`, `ZIP`…) |
| Interactive File Tools (`FileToolOptionsWindowController`) | ✅ `FileToolWindows.swift` | Compress, Strip Meta, Adjust, Frame, Crop, Annotate, Collage, Redact, Trim, Speed, Normalize, PDF Organize |
| QR Code & Barcode scanner (`QRCodeResultsWindowController`) | ✅ `Vision` (`VNDetectBarcodesRequest`) | Scans images and multi-page PDFs with one-click Copy |
| Welcome onboarding & Launch at Login (`SMAppService`) | ✅ `WelcomeWindowController` | Multi-step interactive guide + login item toggle |
| Settings window (Themes, Shortcuts, Formats, Compatibility, Tools) | ✅ `SettingsWindowController` | 4-tab settings with format compatibility matrix |
| Free uses + one-time purchase (RevenueCat) | ❌ removed | 100% open-source & unlocked |

## Install

1. Download `Daisy-<version>.dmg` from
   [Releases](https://github.com/kpostaagasi/daisy/releases/latest).
2. Open it and drag **Daisy** onto **Applications**.
3. Daisy is ad-hoc signed (not notarized), so macOS blocks the first launch.
   Either right-click Daisy → **Open** → **Open**, or run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Daisy.app
   ```

Universal binary (Apple silicon + Intel), macOS 13+.

## Build

```bash
./build.sh          # universal swift build + assemble build/Daisy.app + ad-hoc sign
open build/Daisy.app
./make-dmg.sh       # build + package build/Daisy-<version>.dmg
./make-icon.sh      # regenerate Resources/AppIcon.icns from Resources/AppIcon.svg
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
  AppDelegate.swift        orchestrates wheels, drag monitor, floats, progress HUD, and tools
  AppSettings.swift        UserDefaults-backed settings, themes, modifier shortcuts, LoginItemController
  ConversionTarget.swift   formats (ConversionFormat), tools (FileTool), actions (ConversionFanAction)
  ConversionEngine.swift   executes format conversions and file tools (CoreImage, CoreGraphics, PDFKit, Vision, ffmpeg, cwebp, exiftool)
  ConversionTaskStore.swift active task tracking for menu bar status
  DragGestureMonitor.swift global drag-and-modifier monitor (⌥ Conversions, ⌘ Tools, ⌃ Actions)
  FanView.swift            372×372 radial fan with annular wedge petals (FormatDropTarget) & FanCenterLabelView
  FloatingDropPanel.swift  ConversionOverlayPanel + OperationProgressWindowController & OrangeIndeterminateProgressView
  FloatingFileShelf.swift  FloatingFileWindowController ("Float" shelf & edge paperclip tab) + Clipboard/Move/Terminal/AirDrop actions
  FileToolWindows.swift    FileToolOptionsWindowController + QRCodeResultsWindowController
  MenuBarController.swift  dynamic status bar menu + drag-on-icon receiver
  SettingsWindow.swift     4-tab Settings UI + WelcomeWindowController onboarding
  ToolLocator.swift        Homebrew & bundle tool auto-detection
  ToolRunner.swift         external process runner with timeout & pipe draining
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
