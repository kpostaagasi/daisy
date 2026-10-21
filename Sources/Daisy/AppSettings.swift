// Daisy — user-configurable settings and models inspired by Tangerine.
import AppKit
import Combine
import Foundation
import ServiceManagement

// MARK: - Core Enums & Models (matching Tangerine's domain model)

enum ConversionFanTheme: String, CaseIterable, Codable, Identifiable {
    case glass
    case metallic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return "Glass"
        case .metallic: return "Metallic"
        }
    }
}

enum FloatWheelBehavior: String, CaseIterable, Codable, Identifiable {
    case createNew
    case addToExisting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createNew: return "Create a New Float"
        case .addToExisting: return "Add Files to an Existing Float"
        }
    }
}

enum ConversionFanMode: Int, CaseIterable, Identifiable {
    case conversions = 0
    case fileTools = 1
    case fileActions = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .conversions: return "Conversions"
        case .fileTools: return "Tools"
        case .fileActions: return "Actions"
        }
    }

    var shortTitle: String {
        switch self {
        case .conversions: return "Convert"
        case .fileTools: return "Tools"
        case .fileActions: return "Actions"
        }
    }

    var symbolName: String {
        switch self {
        case .conversions: return "arrow.triangle.2.circlepath"
        case .fileTools: return "wrench.and.screwdriver"
        case .fileActions: return "bolt.fill"
        }
    }
}

enum ConversionQuality: String, CaseIterable, Codable, Identifiable {
    case compact
    case balanced
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .balanced: return "Balanced"
        case .high: return "High"
        }
    }

    var imageCompressionQuality: CGFloat {
        switch self {
        case .compact: return 0.65
        case .balanced: return 0.82
        case .high: return 0.94
        }
    }

    var webpQuality: Int {
        switch self {
        case .compact: return 68
        case .balanced: return 82
        case .high: return 93
        }
    }

    var videoCRF: Int {
        switch self {
        case .compact: return 27
        case .balanced: return 22
        case .high: return 18
        }
    }
}

enum CompressionLevel: String, CaseIterable, Codable, Identifiable {
    case fast
    case balanced
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .maximum: return "Maximum"
        }
    }
}

enum AudioSampleDepth: String, CaseIterable, Codable, Identifiable {
    case matchSource
    case bit16
    case bit24
    case bit32
    case float32

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matchSource: return "Match Source"
        case .bit16: return "16-bit"
        case .bit24: return "24-bit"
        case .bit32: return "32-bit"
        case .float32: return "32-bit Float"
        }
    }
}

enum EPUBLayout: String, CaseIterable, Codable, Identifiable {
    case adjustableText
    case preservePages

    var id: String { rawValue }
    var title: String {
        switch self {
        case .adjustableText: return "Adjustable text"
        case .preservePages: return "Preserve original pages"
        }
    }
}

enum PDFOfficeLayout: String, CaseIterable, Codable, Identifiable {
    case editable
    case preservePages

    var id: String { rawValue }
    var title: String {
        switch self {
        case .editable: return "Editable paragraphs"
        case .preservePages: return "Preserve original pages"
        }
    }
}

struct ConversionOptions: Codable, Equatable {
    var quality: ConversionQuality = .balanced
    var preserveMetadata: Bool = true
    var videoMaxHeight: Int = 0 // 0 = Original, 2160, 1440, 1080, 720, 480
    var audioBitrate: Int = 192 // kbps
    var audioSampleDepth: AudioSampleDepth = .matchSource
    var gifFrameRate: Int = 15
    var gifMaxWidth: Int = 640
    var compression: CompressionLevel = .balanced
    var epubLayout: EPUBLayout = .adjustableText
    var epubReflowVersion: Int = 1
    var pdfOfficeLayout: PDFOfficeLayout = .editable
}

extension ConversionOptions {
    /// Fields missing from an older or partial profile, or unreadable, keep their default values.
    /// The extension keeps the synthesized memberwise and no-argument initializers.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quality = (try? c.decodeIfPresent(ConversionQuality.self, forKey: .quality)) ?? quality
        preserveMetadata = (try? c.decodeIfPresent(Bool.self, forKey: .preserveMetadata)) ?? preserveMetadata
        videoMaxHeight = (try? c.decodeIfPresent(Int.self, forKey: .videoMaxHeight)) ?? videoMaxHeight
        audioBitrate = (try? c.decodeIfPresent(Int.self, forKey: .audioBitrate)) ?? audioBitrate
        audioSampleDepth = (try? c.decodeIfPresent(AudioSampleDepth.self, forKey: .audioSampleDepth)) ?? audioSampleDepth
        gifFrameRate = (try? c.decodeIfPresent(Int.self, forKey: .gifFrameRate)) ?? gifFrameRate
        gifMaxWidth = (try? c.decodeIfPresent(Int.self, forKey: .gifMaxWidth)) ?? gifMaxWidth
        compression = (try? c.decodeIfPresent(CompressionLevel.self, forKey: .compression)) ?? compression
        epubLayout = (try? c.decodeIfPresent(EPUBLayout.self, forKey: .epubLayout)) ?? epubLayout
        epubReflowVersion = (try? c.decodeIfPresent(Int.self, forKey: .epubReflowVersion)) ?? epubReflowVersion
        pdfOfficeLayout = (try? c.decodeIfPresent(PDFOfficeLayout.self, forKey: .pdfOfficeLayout)) ?? pdfOfficeLayout
    }
}

enum ImageCompressionStrength: String, CaseIterable, Codable, Identifiable {
    case balanced
    case strong

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .balanced: return "Better visual quality with moderate file-size savings."
        case .strong: return "Much smaller files with more visible quality loss."
        }
    }
}

enum ImageCompressionSize: String, CaseIterable, Codable, Identifiable {
    case original
    case large
    case medium
    case small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Keep original dimensions"
        case .large: return "2560 px longest edge"
        case .medium: return "1920 px longest edge"
        case .small: return "1280 px longest edge"
        }
    }

    var maxPixelDimension: Int? {
        switch self {
        case .original: return nil
        case .large: return 2560
        case .medium: return 1920
        case .small: return 1280
        }
    }
}

struct ImageCompressionOptions: Codable, Equatable {
    var strength: ImageCompressionStrength = .balanced
    var size: ImageCompressionSize = .original
}

enum VideoCompressionStrength: String, CaseIterable, Codable, Identifiable {
    case balanced
    case strong

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .balanced: return "Smaller files with less quality loss."
        case .strong: return "Smaller files with more quality loss."
        }
    }
}

struct VideoCompressionOptions: Codable, Equatable {
    var strength: VideoCompressionStrength = .balanced
}

// MARK: - Drag Modifier Combinations (matching Tangerine's DragModifierCombination)

struct DragModifierCombination: Equatable, Hashable, Identifiable {
    let mask: UInt

    var id: UInt { mask }

    static let option = DragModifierCombination(mask: NSEvent.ModifierFlags.option.rawValue)
    static let command = DragModifierCombination(mask: NSEvent.ModifierFlags.command.rawValue)
    static let control = DragModifierCombination(mask: NSEvent.ModifierFlags.control.rawValue)
    static let shift = DragModifierCombination(mask: NSEvent.ModifierFlags.shift.rawValue)
    static let optionCommand = DragModifierCombination(
        mask: NSEvent.ModifierFlags([.option, .command]).rawValue
    )
    static let controlOption = DragModifierCombination(
        mask: NSEvent.ModifierFlags([.control, .option]).rawValue
    )

    static let presets: [DragModifierCombination] = [
        .option,
        .command,
        .control,
        .shift,
        .optionCommand,
        .controlOption,
    ]

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: mask)
        if flags.contains(.control) { parts.append("⌃ Control") }
        if flags.contains(.option) { parts.append("⌥ Option") }
        if flags.contains(.shift) { parts.append("⇧ Shift") }
        if flags.contains(.command) { parts.append("⌘ Command") }
        return parts.isEmpty ? "Unset" : parts.joined(separator: " + ")
    }

    var symbolsString: String {
        var out = ""
        let flags = NSEvent.ModifierFlags(rawValue: mask)
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out.isEmpty ? "—" : out
    }
}

// MARK: - Terminal Application

struct TerminalApplication: Identifiable, Equatable {
    let id: String // bundle identifier
    let title: String

    static let supported: [TerminalApplication] = [
        TerminalApplication(id: "com.apple.Terminal", title: "Terminal"),
        TerminalApplication(id: "com.googlecode.iterm2", title: "iTerm2"),
    ]

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }
}

// MARK: - Login Item Controller

enum LoginItemState: Equatable {
    case off
    case on
    case needsApproval
    case unavailable
}

final class LoginItemController: ObservableObject {
    static let shared = LoginItemController()

    @Published private(set) var state: LoginItemState = .off
    @Published var errorMessage: String?

    private init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            state = .on
        case .requiresApproval:
            state = .needsApproval
        case .notRegistered, .notFound:
            state = .off
        @unknown default:
            state = .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            errorMessage = "Couldn’t update launch at login. You can set it up in System Settings → Login Items."
        }
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

// MARK: - AppSettings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var conversionFanTheme: ConversionFanTheme {
        didSet {
            save("conversionFanTheme", conversionFanTheme.rawValue)
            NotificationCenter.default.post(name: .daisyFanThemeDidChange, object: nil)
        }
    }

    @Published var hapticFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticFeedbackEnabled, forKey: "hapticFeedbackEnabled") }
    }

    @Published var floatWheelBehavior: FloatWheelBehavior {
        didSet { save("floatWheelBehavior", floatWheelBehavior.rawValue) }
    }

    @Published var conversionDragModifierMask: UInt {
        didSet { UserDefaults.standard.set(Int(conversionDragModifierMask), forKey: "conversionWheelDragModifierMask") }
    }

    @Published var toolsDragModifierMask: UInt {
        didSet { UserDefaults.standard.set(Int(toolsDragModifierMask), forKey: "toolsWheelDragModifierMask") }
    }

    @Published var actionsDragModifierMask: UInt {
        didSet { UserDefaults.standard.set(Int(actionsDragModifierMask), forKey: "actionsWheelDragModifierMask") }
    }

    @Published var terminalApplicationID: String {
        didSet { save("fileActionsTerminalApplication", terminalApplicationID) }
    }

    @Published var imageCompressionOptions: ImageCompressionOptions {
        didSet {
            save("defaultImageCompressionStrength", imageCompressionOptions.strength.rawValue)
            save("defaultImageCompressionSize", imageCompressionOptions.size.rawValue)
        }
    }

    @Published var videoCompressionOptions: VideoCompressionOptions {
        didSet {
            save("defaultVideoCompressionStrength", videoCompressionOptions.strength.rawValue)
        }
    }

    /// Path to the ffmpeg binary. Empty = automatic lookup.
    @Published var ffmpegPath: String {
        didSet { save("ffmpegPath", ffmpegPath) }
    }
    /// Path to the cwebp binary (WebP encoder).
    @Published var cwebpPath: String {
        didSet { save("cwebpPath", cwebpPath) }
    }
    /// Path to the exiftool binary (metadata tools).
    @Published var exiftoolPath: String {
        didSet { save("exiftoolPath", exiftoolPath) }
    }
    /// Where converted files are written. Empty = alongside the source file.
    @Published var outputDirectory: String {
        didSet { save("outputDirectory", outputDirectory) }
    }
    /// Per-file conversion timeout in seconds.
    @Published var timeoutSeconds: Int {
        didSet { UserDefaults.standard.set(timeoutSeconds, forKey: "timeoutSeconds") }
    }

    @Published var hasCompletedWelcome: Bool {
        didSet { UserDefaults.standard.set(hasCompletedWelcome, forKey: "hasCompletedWelcome") }
    }

    @Published var automaticallyChecksForUpdates: Bool {
        didSet { UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates") }
    }

    init() {
        let d = UserDefaults.standard
        conversionFanTheme = ConversionFanTheme(rawValue: d.string(forKey: "conversionFanTheme") ?? "") ?? .glass
        // Carries over the old combined sound-and-haptics switch.
        hapticFeedbackEnabled = d.object(forKey: "hapticFeedbackEnabled") as? Bool
            ?? d.object(forKey: "soundsAndHapticsEnabled") as? Bool
            ?? true
        floatWheelBehavior = FloatWheelBehavior(rawValue: d.string(forKey: "floatWheelBehavior") ?? "") ?? .addToExisting

        var storedDragMasks: [ConversionFanMode: UInt] = [:]
        let dragMaskKeys: [(ConversionFanMode, String)] = [
            (.conversions, "conversionWheelDragModifierMask"),
            (.fileTools, "toolsWheelDragModifierMask"),
            (.fileActions, "actionsWheelDragModifierMask"),
        ]
        for (mode, key) in dragMaskKeys {
            if let v = d.object(forKey: key) as? Int, v > 0 {
                storedDragMasks[mode] = UInt(v)
            }
        }
        let dragMasks = Self.resolvedDragMasks(storedDragMasks)
        conversionDragModifierMask = dragMasks[.conversions, default: Self.defaultDragMask(for: .conversions)]
        toolsDragModifierMask = dragMasks[.fileTools, default: Self.defaultDragMask(for: .fileTools)]
        actionsDragModifierMask = dragMasks[.fileActions, default: Self.defaultDragMask(for: .fileActions)]

        terminalApplicationID = d.string(forKey: "fileActionsTerminalApplication") ?? "com.apple.Terminal"

        let imgStrength = ImageCompressionStrength(rawValue: d.string(forKey: "defaultImageCompressionStrength") ?? "") ?? .balanced
        let imgSize = ImageCompressionSize(rawValue: d.string(forKey: "defaultImageCompressionSize") ?? "") ?? .original
        imageCompressionOptions = ImageCompressionOptions(strength: imgStrength, size: imgSize)

        let vidStrength = VideoCompressionStrength(rawValue: d.string(forKey: "defaultVideoCompressionStrength") ?? "") ?? .balanced
        videoCompressionOptions = VideoCompressionOptions(strength: vidStrength)

        ffmpegPath = d.string(forKey: "ffmpegPath") ?? ""
        cwebpPath = d.string(forKey: "cwebpPath") ?? ""
        exiftoolPath = d.string(forKey: "exiftoolPath") ?? ""
        outputDirectory = d.string(forKey: "outputDirectory") ?? ""
        timeoutSeconds = d.object(forKey: "timeoutSeconds") as? Int ?? 300
        hasCompletedWelcome = d.bool(forKey: "hasCompletedWelcome")
        automaticallyChecksForUpdates = d.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
    }

    func options(for format: ConversionFormat) -> ConversionOptions {
        let key = "conversionProfile.\(format.rawValue)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ConversionOptions.self, from: data) {
            return decoded
        }
        return ConversionOptions()
    }

    func setOptions(_ options: ConversionOptions, for format: ConversionFormat) {
        let key = "conversionProfile.\(format.rawValue)"
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: key)
        }
        objectWillChange.send()
    }

    func resetOptions(for format: ConversionFormat) {
        UserDefaults.standard.removeObject(forKey: "conversionProfile.\(format.rawValue)")
        objectWillChange.send()
    }

    func resetCompressionDefaults() {
        imageCompressionOptions = ImageCompressionOptions()
        videoCompressionOptions = VideoCompressionOptions()
    }

    func matchingMode(for modifiers: NSEvent.ModifierFlags) -> ConversionFanMode? {
        let masked = modifiers.intersection([.control, .option, .shift, .command]).rawValue
        guard masked != 0 else { return nil }
        if masked == conversionDragModifierMask { return .conversions }
        if masked == toolsDragModifierMask { return .fileTools }
        if masked == actionsDragModifierMask { return .fileActions }
        return nil
    }

    func dragModifierMask(for mode: ConversionFanMode) -> UInt {
        switch mode {
        case .conversions: return conversionDragModifierMask
        case .fileTools: return toolsDragModifierMask
        case .fileActions: return actionsDragModifierMask
        }
    }

    /// Assigns `mask` to `mode`. If another wheel already uses `mask`, that wheel takes `mode`'s previous mask,
    /// so two wheels never share a modifier combination.
    func setDragModifier(_ mask: UInt, for mode: ConversionFanMode) {
        guard mask != 0 else { return }
        let previous = dragModifierMask(for: mode)
        for other in ConversionFanMode.allCases where other != mode && dragModifierMask(for: other) == mask {
            assignDragModifierMask(previous, for: other)
        }
        assignDragModifierMask(mask, for: mode)
    }

    private func assignDragModifierMask(_ mask: UInt, for mode: ConversionFanMode) {
        switch mode {
        case .conversions: conversionDragModifierMask = mask
        case .fileTools: toolsDragModifierMask = mask
        case .fileActions: actionsDragModifierMask = mask
        }
    }

    static func defaultDragMask(for mode: ConversionFanMode) -> UInt {
        switch mode {
        case .conversions: return NSEvent.ModifierFlags.option.rawValue
        case .fileTools: return NSEvent.ModifierFlags.command.rawValue
        case .fileActions: return NSEvent.ModifierFlags.control.rawValue
        }
    }

    /// Keeps each wheel's stored mask unless an earlier wheel already holds it. Then tries the wheel's default,
    /// then the first preset nobody holds. Result: no two wheels share a mask.
    static func resolvedDragMasks(_ stored: [ConversionFanMode: UInt]) -> [ConversionFanMode: UInt] {
        var resolved: [ConversionFanMode: UInt] = [:]
        for mode in ConversionFanMode.allCases {
            let taken = Set(resolved.values)
            let candidates = [stored[mode] ?? defaultDragMask(for: mode), defaultDragMask(for: mode)] +
                DragModifierCombination.presets.map(\.mask)
            resolved[mode] = candidates.first(where: { !taken.contains($0) }) ?? defaultDragMask(for: mode)
        }
        return resolved
    }

    var modifierSymbolForMode: (ConversionFanMode) -> String {
        { [weak self] mode in
            guard let self else { return "" }
            switch mode {
            case .conversions:
                return DragModifierCombination(mask: self.conversionDragModifierMask).symbolsString
            case .fileTools:
                return DragModifierCombination(mask: self.toolsDragModifierMask).symbolsString
            case .fileActions:
                return DragModifierCombination(mask: self.actionsDragModifierMask).symbolsString
            }
        }
    }

    private func save(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Notification.Name {
    static let daisyOpenSettings = Notification.Name("daisy.openSettings")
    static let daisyOpenWelcome = Notification.Name("daisy.openWelcome")
    static let daisyFanThemeDidChange = Notification.Name("io.daisy.Daisy.conversionFanThemeDidChange")
}
