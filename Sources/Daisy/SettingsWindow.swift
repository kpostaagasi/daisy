// Daisy — SettingsWindowController and WelcomeWindowController inspired by Tangerine.
import AppKit
import SwiftUI

// MARK: - Settings View (matching Tangerine's TangerineSettingsView + Daisy tool paths)

struct DaisySettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem = LoginItemController.shared
    @ObservedObject var updates = UpdateController.shared
    @State private var selectedTab: Int = 0
    @State private var selectedFormat: ConversionFormat = .webp
    @State private var formatOptions: ConversionOptions = AppSettings.shared.options(for: .webp)
    @State private var selectedCompatibilityGroup: SupportedFormatGroup = .images

    private let accent = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1.0))

    var body: some View {
        VStack(spacing: 0) {
            // Top segmented navigation
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("General").tag(0)
                    Text("Conversions").tag(1)
                    Text("Compatibility").tag(2)
                    Text("Tools & Paths").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case 0:
                        generalTab
                    case 1:
                        conversionsTab
                    case 2:
                        compatibilityTab
                    default:
                        toolsTab
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 460)
        .onChange(of: selectedFormat) { newFmt in
            formatOptions = settings.options(for: newFmt)
        }
    }

    // MARK: - Tab 0: General & Shortcuts

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("Appearance & Behavior", systemImage: "sparkles")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Launch Daisy at login")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { loginItem.state == .on },
                            set: { loginItem.setEnabled($0) }
                        ))
                        .labelsHidden()
                    }
                    if loginItem.state == .needsApproval {
                        HStack {
                            Text("Allow Daisy in macOS Login Items to finish setup.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Open Login Items") {
                                loginItem.openSystemSettingsLoginItems()
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Conversion fan theme")
                        Spacer()
                        Picker("", selection: $settings.conversionFanTheme) {
                            ForEach(ConversionFanTheme.allCases) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Haptic feedback")
                            Text("Trackpad clicks as you move across petals, switch modes and drop files.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.hapticFeedbackEnabled)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Float wheel behavior")
                        Spacer()
                        Picker("", selection: $settings.floatWheelBehavior) {
                            ForEach(FloatWheelBehavior.allCases) { b in
                                Text(b.title).tag(b)
                            }
                        }
                        .frame(width: 240)
                    }

                    HStack {
                        Text("Terminal application")
                        Spacer()
                        Picker("", selection: $settings.terminalApplicationID) {
                            ForEach(TerminalApplication.supported) { app in
                                Text(app.isInstalled ? app.title : "\(app.title) (Not installed)").tag(app.id)
                            }
                        }
                        .frame(width: 200)
                    }
                }
                .padding(8)
            }

            GroupBox(label: Label("Drag-to-Open Wheel Shortcuts", systemImage: "command")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tap the chosen modifier combination while dragging files from Finder or any app.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    shortcutRow(title: "Conversion wheel", mode: .conversions)
                    shortcutRow(title: "Tools wheel", mode: .fileTools)
                    shortcutRow(title: "Actions wheel", mode: .fileActions)
                }
                .padding(8)
            }

            GroupBox(label: Label("Updates", systemImage: "arrow.down.circle")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Automatically check for updates")
                        Spacer()
                        Toggle("", isOn: $settings.automaticallyChecksForUpdates)
                            .labelsHidden()
                    }
                    HStack {
                        Text(updateStatusText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Check Now") {
                            updates.check(userInitiated: true)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("Full version unlocked — Daisy is 100% open-source with unlimited conversions and tools.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var updateStatusText: String {
        var text = "Daisy \(updates.currentVersion)"
        if let release = updates.availableRelease {
            text += " · \(release.version) available"
        } else if let last = updates.lastCheck {
            text += " · checked \(last.formatted(.relative(presentation: .named)))"
        }
        return text
    }

    private func shortcutRow(title: String, mode: ConversionFanMode) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: Binding(
                get: { settings.dragModifierMask(for: mode) },
                set: { settings.setDragModifier($0, for: mode) }
            )) {
                ForEach(DragModifierCombination.presets) { combo in
                    Text(combo.displayString).tag(combo.mask)
                }
            }
            .frame(width: 200)
        }
    }

    // MARK: - Tab 1: Conversions & Compression Defaults

    private var conversionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("Per-Format Conversion Defaults", systemImage: "slider.horizontal.3")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Output format")
                        Spacer()
                        Picker("", selection: $selectedFormat) {
                            ForEach(ConversionFormat.allCases) { fmt in
                                Text("\(fmt.title) (.\(fmt.fileExtension))").tag(fmt)
                            }
                        }
                        .frame(width: 200)
                    }

                    Divider()

                    HStack {
                        Text("Quality")
                        Spacer(minLength: 8)
                        Picker("", selection: $formatOptions.quality) {
                            ForEach(ConversionQuality.allCases) { q in
                                Text(q.title).tag(q)
                            }
                        }
                        .frame(width: 160)
                    }

                    HStack {
                        Text("Preserve metadata")
                        Spacer()
                        Toggle("", isOn: $formatOptions.preserveMetadata)
                            .labelsHidden()
                    }

                    if selectedFormat.group == .video {
                        HStack {
                            Text("Maximum video height")
                            Spacer()
                            Picker("", selection: $formatOptions.videoMaxHeight) {
                                Text("Original").tag(0)
                                Text("2160p (4K)").tag(2160)
                                Text("1440p").tag(1440)
                                Text("1080p").tag(1080)
                                Text("720p").tag(720)
                                Text("480p").tag(480)
                            }
                            .frame(width: 160)
                        }
                    }

                    if selectedFormat == .gif {
                        HStack {
                            Text("GIF frame rate: \(formatOptions.gifFrameRate) fps")
                            Spacer()
                            Stepper("", value: $formatOptions.gifFrameRate, in: 5...30)
                        }
                        HStack {
                            Text("GIF maximum width: \(formatOptions.gifMaxWidth) px")
                            Spacer()
                            Stepper("", value: $formatOptions.gifMaxWidth, in: 240...1920, step: 80)
                        }
                    }

                    if selectedFormat.group == .audio || selectedFormat.group == .video {
                        HStack {
                            Text("Audio bitrate")
                            Spacer()
                            Picker("", selection: $formatOptions.audioBitrate) {
                                Text("128 kbps").tag(128)
                                Text("192 kbps").tag(192)
                                Text("256 kbps").tag(256)
                                Text("320 kbps").tag(320)
                            }
                            .frame(width: 140)
                        }
                    }

                    HStack {
                        Button("Restore Format Defaults") {
                            settings.resetOptions(for: selectedFormat)
                            formatOptions = settings.options(for: selectedFormat)
                        }
                        .controlSize(.small)
                        Spacer()
                        Button("Save Format Defaults") {
                            settings.setOptions(formatOptions, for: selectedFormat)
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                }
                .padding(8)
            }

            GroupBox(label: Label("Compression Tool Defaults", systemImage: "arrow.down.right.and.arrow.up.left")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Image compression strength")
                        Spacer()
                        Picker("", selection: $settings.imageCompressionOptions.strength) {
                            ForEach(ImageCompressionStrength.allCases) { s in
                                Text(s.title).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    HStack {
                        Text("Image max dimensions")
                        Spacer()
                        Picker("", selection: $settings.imageCompressionOptions.size) {
                            ForEach(ImageCompressionSize.allCases) { sz in
                                Text(sz.title).tag(sz)
                            }
                        }
                        .frame(width: 220)
                    }
                    HStack {
                        Text("Video compression strength")
                        Spacer()
                        Picker("", selection: $settings.videoCompressionOptions.strength) {
                            ForEach(VideoCompressionStrength.allCases) { s in
                                Text(s.title).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    HStack {
                        Spacer()
                        Button("Restore Compression Defaults") {
                            settings.resetCompressionDefaults()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Tab 2: Format Compatibility Matrix

    private var compatibilityTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Category", selection: $selectedCompatibilityGroup) {
                ForEach(SupportedFormatGroup.allCases) { grp in
                    Text(grp.title).tag(grp)
                }
            }
            .pickerStyle(.menu)

            ForEach(selectedCompatibilityGroup.formats) { fmt in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(fmt.title)
                            .font(.system(size: 12.5, weight: .bold))
                        Text(".\(fmt.fileExtension)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(fmt.supportedOutputs.count) output targets")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    Text("Converts to: " + fmt.supportedOutputs.map(\.title).joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tab 3: External Tools & Output Folder

    private var toolsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("Detected External Tools", systemImage: "wrench.and.screwdriver")) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ToolLocator.toolStatus(settings), id: \.name) { item in
                        HStack {
                            Image(systemName: item.found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(item.found ? .green : .orange)
                            Text(item.name)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 70, alignment: .leading)
                            Text(item.found ? item.path : "Not found (brew install \(item.name == "cwebp" ? "webp" : item.name))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }

                    Divider()

                    toolFieldRow("ffmpeg path override (empty = auto)", text: $settings.ffmpegPath)
                    toolFieldRow("cwebp path override (empty = auto)", text: $settings.cwebpPath)
                    toolFieldRow("exiftool path override (empty = auto)", text: $settings.exiftoolPath)
                }
                .padding(8)
            }

            GroupBox(label: Label("Output Location & Timeout", systemImage: "folder")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Output folder (empty = save alongside original file)")
                        .font(.system(size: 11, weight: .medium))
                    HStack {
                        TextField("Alongside source file", text: $settings.outputDirectory)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK, let url = panel.url {
                                settings.outputDirectory = url.path
                            }
                        }
                        .controlSize(.small)
                        if !settings.outputDirectory.isEmpty {
                            Button("Clear") {
                                settings.outputDirectory = ""
                            }
                            .controlSize(.small)
                        }
                    }

                    HStack {
                        Text("Per-file conversion timeout (seconds)")
                        Spacer()
                        Stepper("\(settings.timeoutSeconds)s", value: $settings.timeoutSeconds, in: 30...1800, step: 30)
                    }
                }
                .padding(8)
            }
        }
    }

    private func toolFieldRow(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("Auto-detect in /opt/homebrew/bin, /usr/local/bin", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}

final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Daisy Settings"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: DaisySettingsView(settings: settings))
        window.setContentSize(NSSize(width: 560, height: 460))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func show() {
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Welcome / Onboarding Window (matching Tangerine's WelcomeWindowController & WelcomeView at 0x10033df38)

enum WelcomePage: Int, CaseIterable {
    case welcome = 0
    case converter = 1
    case tools = 2
    case actions = 3
    case setup = 4
}

struct DaisyWelcomeView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var loginItem = LoginItemController.shared
    @State private var page: WelcomePage = .welcome

    var onTryWheel: ((ConversionFanMode) -> Void)?
    var onClose: (() -> Void)?

    private let accent = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1.0))

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 4)

            switch page {
            case .welcome:
                welcomeStep(
                    symbol: "camera.macro.circle.fill",
                    title: "Welcome to Daisy",
                    subtitle: "Instant radial file conversions, quick tools, and floating file shelves — right at your cursor.",
                    badge: "Step 1. Drag files in Finder.   Step 2. Tap ⌥, ⌘, or ⌃ while dragging."
                )
            case .converter:
                welcomeStep(
                    symbol: "arrow.triangle.2.circlepath.circle.fill",
                    title: "Conversion Wheel (\(DragModifierCombination(mask: settings.conversionDragModifierMask).symbolsString))",
                    subtitle: "While dragging any image, video, audio, document, subtitle, or archive, tap \(DragModifierCombination(mask: settings.conversionDragModifierMask).displayString) to bloom the format wheel around your cursor.",
                    badge: "Images · Video · Audio · PDF · Subtitles · Archives"
                )
            case .tools:
                welcomeStep(
                    symbol: "wrench.and.screwdriver.fill",
                    title: "File Tools Wheel (\(DragModifierCombination(mask: settings.toolsDragModifierMask).symbolsString))",
                    subtitle: "Tap \(DragModifierCombination(mask: settings.toolsDragModifierMask).displayString) while dragging to compress, strip metadata, frame screenshots, annotate, redact faces, create collages, scan QR codes, or trim media.",
                    badge: "Compress · Strip Meta · Frame · Annotate · Redact · Collage · QR Code · Trim · Normalize"
                )
            case .actions:
                welcomeStep(
                    symbol: "paperclip.circle.fill",
                    title: "Actions & Float Shelf (\(DragModifierCombination(mask: settings.actionsDragModifierMask).symbolsString))",
                    subtitle: "Tap \(DragModifierCombination(mask: settings.actionsDragModifierMask).displayString) while dragging to pin files to a Floating Shelf on your screen edge, AirDrop, Copy Paths, Move, or open Terminal.",
                    badge: "Float Shelf · AirDrop · Copy · Move · Copy Path · Open Terminal"
                )
            case .setup:
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 46))
                        .foregroundColor(accent)
                    Text("Ready Whenever You Need It")
                        .font(.system(size: 20, weight: .bold))
                    Text("Find the Daisy icon near the clock in your menu bar, or drag any file and tap a modifier key.")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)

                    Toggle("Launch Daisy at login", isOn: Binding(
                        get: { loginItem.state == .on },
                        set: { loginItem.setEnabled($0) }
                    ))
                    .padding(.top, 4)

                    HStack(spacing: 10) {
                        Button("Try Conversion Wheel") {
                            onTryWheel?(.conversions)
                        }
                        Button("Try Tools Wheel") {
                            onTryWheel?(.fileTools)
                        }
                        Button("Try Actions Wheel") {
                            onTryWheel?(.fileActions)
                        }
                    }
                    .controlSize(.small)
                }
            }

            Spacer()

            // Page dots & navigation buttons
            HStack {
                if page != .welcome {
                    Button("Back") {
                        if let prev = WelcomePage(rawValue: page.rawValue - 1) {
                            page = prev
                        }
                    }
                } else {
                    Button("Skip") {
                        settings.hasCompletedWelcome = true
                        onClose?()
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(WelcomePage.allCases, id: \.rawValue) { p in
                        Circle()
                            .fill(p == page ? accent : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if page != .setup {
                    Button("Continue") {
                        if let next = WelcomePage(rawValue: page.rawValue + 1) {
                            page = next
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                } else {
                    Button("Get Started") {
                        settings.hasCompletedWelcome = true
                        onClose?()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
    }

    private func welcomeStep(symbol: String, title: String, subtitle: String, badge: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundColor(accent)
            Text(title)
                .font(.system(size: 19, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
            Text(badge)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(accent.opacity(0.14))
                .cornerRadius(8)
        }
    }
}

final class WelcomeWindowController: NSWindowController {
    var onTryWheel: ((ConversionFanMode) -> Void)?

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Daisy"
        window.titlebarAppearsTransparent = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        super.init(window: window)

        let view = DaisyWelcomeView(
            onTryWheel: { [weak self] mode in
                self?.onTryWheel?(mode)
            },
            onClose: { [weak self] in
                self?.window?.close()
            }
        )
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(NSSize(width: 480, height: 360))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func show() {
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
