// Daisy — formats, file tools, fan actions, and tool option models inspired by Tangerine.
import AppKit
import Foundation

// MARK: - Supported Format Groups & Formats

enum SupportedFormatGroup: String, CaseIterable, Identifiable {
    case images
    case video
    case audio
    case documents
    case spreadsheets
    case subtitles
    case archives

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: return "Images"
        case .video: return "Video"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .spreadsheets: return "Spreadsheets"
        case .subtitles: return "Subtitles"
        case .archives: return "Archives"
        }
    }

    var symbolName: String {
        switch self {
        case .images: return "photo.on.rectangle.angled"
        case .video: return "film"
        case .audio: return "waveform"
        case .documents: return "doc.richtext"
        case .spreadsheets: return "tablecells"
        case .subtitles: return "captions.bubble"
        case .archives: return "archivebox"
        }
    }

    var formats: [ConversionFormat] {
        ConversionFormat.allCases.filter { $0.group == self }
    }
}

enum ConversionFormat: String, CaseIterable, Codable, Identifiable, Hashable {
    // Images
    case jpg
    case png
    case webp
    case heic
    case tiff
    case bmp
    case avif
    case svg
    case gif
    // Documents
    case pdf
    case docx
    case txt
    case md
    case rtf
    case html
    case epub
    // Audio
    case mp3
    case m4a
    case wav
    case flac
    case ogg
    case opus
    case aiff
    // Video
    case mp4
    case mov
    case mkv
    case webm
    case avi
    // Spreadsheets
    case csv
    case tsv
    // Subtitles
    case srt
    case vtt
    // Archives
    case zip
    case tar
    case gz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpg: return "JPG"
        case .png: return "PNG"
        case .webp: return "WebP"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .bmp: return "BMP"
        case .avif: return "AVIF"
        case .svg: return "SVG"
        case .gif: return "GIF"
        case .pdf: return "PDF"
        case .docx: return "DOCX"
        case .txt: return "TXT"
        case .md: return "MD"
        case .rtf: return "RTF"
        case .html: return "HTML"
        case .epub: return "EPUB"
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .wav: return "WAV"
        case .flac: return "FLAC"
        case .ogg: return "OGG"
        case .opus: return "OPUS"
        case .aiff: return "AIFF"
        case .mp4: return "MP4"
        case .mov: return "MOV"
        case .mkv: return "MKV"
        case .webm: return "WebM"
        case .avi: return "AVI"
        case .csv: return "CSV"
        case .tsv: return "TSV"
        case .srt: return "SRT"
        case .vtt: return "VTT"
        case .zip: return "ZIP"
        case .tar: return "TAR"
        case .gz: return "TAR.GZ"
        }
    }

    var fileExtension: String {
        switch self {
        case .gz: return "tar.gz"
        default: return rawValue
        }
    }

    var group: SupportedFormatGroup {
        switch self {
        case .jpg, .png, .webp, .heic, .tiff, .bmp, .avif, .svg, .gif:
            return .images
        case .pdf, .docx, .txt, .md, .rtf, .html, .epub:
            return .documents
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff:
            return .audio
        case .mp4, .mov, .mkv, .webm, .avi:
            return .video
        case .csv, .tsv:
            return .spreadsheets
        case .srt, .vtt:
            return .subtitles
        case .zip, .tar, .gz:
            return .archives
        }
    }

    var supportedOutputs: [ConversionFormat] {
        switch self {
        case .jpg, .png, .webp, .heic, .tiff, .bmp, .avif:
            return [.webp, .jpg, .png, .heic, .tiff, .bmp, .avif, .pdf, .gif].filter { $0 != self }
        case .svg:
            return [.png, .jpg, .webp, .pdf]
        case .gif:
            return [.mp4, .mov, .png, .jpg]
        case .mp4, .mov, .mkv, .webm, .avi:
            return [.mp4, .mov, .mkv, .webm, .gif, .mp3, .m4a, .wav, .flac].filter { $0 != self }
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff:
            return [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .mp4].filter { $0 != self }
        case .pdf:
            return [.png, .jpg, .webp, .tiff, .txt, .html, .md, .docx]
        case .docx, .rtf, .txt, .md, .html, .epub:
            return [.pdf, .docx, .html, .txt, .md, .rtf].filter { $0 != self }
        case .csv, .tsv:
            return [.csv, .tsv, .html, .md, .pdf, .txt].filter { $0 != self }
        case .srt, .vtt:
            return [.srt, .vtt, .txt].filter { $0 != self }
        case .zip, .tar, .gz:
            return [.zip, .tar, .gz].filter { $0 != self }
        }
    }

    var hasAdjustableDefaults: Bool {
        switch self {
        case .jpg, .webp, .heic, .avif, .png, .mp4, .mov, .mkv, .webm, .gif, .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .zip, .gz, .docx, .epub:
            return true
        default:
            return false
        }
    }

    static func detect(for url: URL) -> ConversionFormat? {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if url.pathExtension.lowercased() == "rtfd" { return .rtf }
            return nil
        }
        let lowerName = url.lastPathComponent.lowercased()
        if lowerName.hasSuffix(".tar.gz") || lowerName.hasSuffix(".tgz") {
            return .gz
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "jfif": return .jpg
        case "png": return .png
        case "webp": return .webp
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        case "bmp": return .bmp
        case "avif": return .avif
        case "svg": return .svg
        case "gif": return .gif
        case "pdf": return .pdf
        case "docx", "doc": return .docx
        case "txt", "text", "log": return .txt
        case "md", "markdown": return .md
        case "rtf", "rtfd": return .rtf
        case "html", "htm", "xhtml": return .html
        case "epub": return .epub
        case "mp3": return .mp3
        case "m4a", "aac": return .m4a
        case "wav", "wave": return .wav
        case "flac": return .flac
        case "ogg", "oga": return .ogg
        case "opus": return .opus
        case "aif", "aiff": return .aiff
        case "mp4", "m4v": return .mp4
        case "mov", "qt": return .mov
        case "mkv": return .mkv
        case "webm": return .webm
        case "avi": return .avi
        case "csv": return .csv
        case "tsv", "tab": return .tsv
        case "srt": return .srt
        case "vtt": return .vtt
        case "zip", "cbz": return .zip
        case "tar": return .tar
        case "gz", "tgz": return .gz
        default: return nil
        }
    }
}

// MARK: - File Tools (matching Tangerine's FileTool enum)

enum FileTool: String, CaseIterable, Codable, Identifiable, Hashable {
    case compress
    case removeMetadata
    case editImage
    case annotateImage
    case frameImage
    case cropImage
    case createCollage
    case readQRCode
    case redactImage
    case normalizeAudio
    case trimAudio
    case audioChannels
    case audioToVideo
    case muteVideo
    case trimVideo
    case cropVideo
    case changeVideoSpeed
    case joinVideos
    case videoSnapshots
    case splitPDF
    case organizePDF
    case mergePDF
    case createPDF
    case extractArchive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compress: return "Compress"
        case .removeMetadata: return "Strip Meta"
        case .editImage: return "Adjust"
        case .annotateImage: return "Annotate"
        case .frameImage: return "Frame"
        case .cropImage: return "Crop"
        case .createCollage: return "Collage"
        case .readQRCode: return "QR Code"
        case .redactImage: return "Redact"
        case .normalizeAudio: return "Normalize"
        case .trimAudio: return "Trim Audio"
        case .audioChannels: return "Channels"
        case .audioToVideo: return "Visualizer"
        case .muteVideo: return "Mute"
        case .trimVideo: return "Trim Video"
        case .cropVideo: return "Crop Video"
        case .changeVideoSpeed: return "Speed"
        case .joinVideos: return "Join Videos"
        case .videoSnapshots: return "Snapshots"
        case .splitPDF: return "Split PDF"
        case .organizePDF: return "Organize"
        case .mergePDF: return "Merge PDF"
        case .createPDF: return "Create PDF"
        case .extractArchive: return "Extract"
        }
    }

    var fullTitle: String {
        switch self {
        case .compress: return "Compress Files"
        case .removeMetadata: return "Remove Metadata"
        case .editImage: return "Adjust Image"
        case .annotateImage: return "Annotate Photo"
        case .frameImage: return "Frame Image"
        case .cropImage: return "Crop Image"
        case .createCollage: return "Create Collage"
        case .readQRCode: return "Read QR Code"
        case .redactImage: return "Redact Photo"
        case .normalizeAudio: return "Normalize Volume"
        case .trimAudio: return "Trim Audio"
        case .audioChannels: return "Convert Audio Channels"
        case .audioToVideo: return "Audio Visualizer"
        case .muteVideo: return "Mute Video"
        case .trimVideo: return "Trim Video"
        case .cropVideo: return "Crop Video"
        case .changeVideoSpeed: return "Change Video Speed"
        case .joinVideos: return "Join Videos"
        case .videoSnapshots: return "Video Snapshots"
        case .splitPDF: return "Split PDF Pages"
        case .organizePDF: return "Organize PDF"
        case .mergePDF: return "Merge PDFs"
        case .createPDF: return "Create PDF"
        case .extractArchive: return "Extract Archive"
        }
    }

    var symbolName: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .removeMetadata: return "tag.slash"
        case .editImage: return "slider.horizontal.3"
        case .annotateImage: return "pencil.and.outline"
        case .frameImage: return "photo.artframe"
        case .cropImage, .cropVideo: return "crop"
        case .createCollage: return "rectangle.3.group"
        case .readQRCode: return "qrcode.viewfinder"
        case .redactImage: return "eye.slash"
        case .normalizeAudio: return "waveform.badge.minus"
        case .trimAudio, .trimVideo: return "timeline.selection"
        case .audioChannels: return "speaker.wave.2"
        case .audioToVideo: return "waveform"
        case .muteVideo: return "speaker.slash.fill"
        case .changeVideoSpeed: return "gauge.with.dots.needle.67percent"
        case .joinVideos: return "rectangle.split.2x1"
        case .videoSnapshots: return "camera.viewfinder"
        case .splitPDF: return "rectangle.split.3x1"
        case .organizePDF: return "square.grid.2x2"
        case .mergePDF, .createPDF: return "doc.on.doc"
        case .extractArchive: return "archivebox"
        }
    }

    var requiresOptionsWindow: Bool {
        switch self {
        case .compress, .editImage, .annotateImage, .frameImage, .cropImage, .createCollage, .redactImage,
             .normalizeAudio, .trimAudio, .audioChannels, .audioToVideo, .trimVideo, .cropVideo, .changeVideoSpeed, .organizePDF:
            return true
        case .removeMetadata, .readQRCode, .muteVideo, .joinVideos, .videoSnapshots, .splitPDF, .mergePDF, .createPDF, .extractArchive:
            return false
        }
    }

    func supports(urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let formats = urls.compactMap { ConversionFormat.detect(for: $0) }
        guard formats.count == urls.count else { return false }
        let images = formats.allSatisfy { $0.group == .images }
        let stillRaster = formats.allSatisfy { $0.group == .images && $0 != .gif && $0 != .svg }
        let rasterImages = formats.allSatisfy { $0.group == .images && $0 != .svg }
        let allVideos = formats.allSatisfy { $0.group == .video }
        let allAudio = formats.allSatisfy { $0.group == .audio }
        let allPDFs = formats.allSatisfy { $0 == .pdf }
        let allArchives = formats.allSatisfy { $0.group == .archives }

        switch self {
        case .compress:
            return stillRaster || allVideos || allPDFs
        case .removeMetadata:
            return rasterImages || allVideos || allAudio || allPDFs
        case .editImage, .frameImage, .cropImage:
            return images
        case .annotateImage:
            return images && urls.count == 1
        case .redactImage:
            return rasterImages && urls.count == 1
        case .createCollage:
            return images && urls.count >= 2
        case .readQRCode:
            return formats.allSatisfy { ($0.group == .images && $0 != .svg) || $0 == .pdf }
        case .normalizeAudio, .trimAudio, .audioChannels, .audioToVideo:
            return allAudio || allVideos
        case .muteVideo, .trimVideo, .cropVideo, .changeVideoSpeed, .videoSnapshots:
            return allVideos
        case .joinVideos:
            return allVideos && urls.count >= 2
        case .splitPDF, .organizePDF:
            return allPDFs && urls.count == 1
        case .mergePDF:
            return allPDFs && urls.count >= 2
        case .createPDF:
            return images && urls.count >= 2
        case .extractArchive:
            return allArchives
        }
    }
}

// MARK: - Conversion Fan Action (Petals across all 3 Wheels)

enum ConversionFanAction: Identifiable, Equatable, Hashable {
    case convert(ConversionFormat)
    case fileTool(FileTool)
    case float
    case airDrop
    case copy
    case move
    case copyPath
    case openTerminal

    var id: String {
        switch self {
        case .convert(let f): return "convert.\(f.rawValue)"
        case .fileTool(let t): return "tool.\(t.rawValue)"
        case .float: return "action.float"
        case .airDrop: return "action.airDrop"
        case .copy: return "action.copy"
        case .move: return "action.move"
        case .copyPath: return "action.copyPath"
        case .openTerminal: return "action.openTerminal"
        }
    }

    var label: String {
        switch self {
        case .convert(let f): return f.title
        case .fileTool(let t): return t.title
        case .float: return "Float"
        case .airDrop: return "AirDrop"
        case .copy: return "Copy"
        case .move: return "Move"
        case .copyPath: return "Copy Path"
        case .openTerminal: return "Terminal"
        }
    }

    var detailTitle: String {
        switch self {
        case .convert(let f): return "Convert to \(f.title)"
        case .fileTool(let t): return t.fullTitle
        case .float: return "Float File Shelf"
        case .airDrop: return "Share with AirDrop"
        case .copy: return "Copy Files"
        case .move: return "Move to Folder…"
        case .copyPath: return "Copy File Paths"
        case .openTerminal: return "Open in Terminal"
        }
    }

    var symbolName: String? {
        switch self {
        case .convert: return nil // Format petals display bold format typography like Tangerine
        case .fileTool(let t): return t.symbolName
        case .float: return "paperclip"
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .copy: return "doc.on.doc"
        case .move: return "folder"
        case .copyPath: return "link"
        case .openTerminal: return "terminal"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .convert(let f):
            switch f.group {
            case .images: return NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1.0)
            case .video: return NSColor(srgbRed: 0.96, green: 0.24, blue: 0.36, alpha: 1.0)
            case .audio: return NSColor(srgbRed: 0.62, green: 0.34, blue: 0.96, alpha: 1.0)
            case .documents: return NSColor(srgbRed: 0.20, green: 0.56, blue: 0.98, alpha: 1.0)
            case .spreadsheets: return NSColor(srgbRed: 0.16, green: 0.74, blue: 0.46, alpha: 1.0)
            case .subtitles: return NSColor(srgbRed: 0.96, green: 0.64, blue: 0.12, alpha: 1.0)
            case .archives: return NSColor(srgbRed: 0.56, green: 0.62, blue: 0.72, alpha: 1.0)
            }
        case .fileTool:
            return NSColor(srgbRed: 1.0, green: 0.32, blue: 0.0, alpha: 1.0)
        case .float, .airDrop, .copy, .move, .copyPath, .openTerminal:
            return NSColor(srgbRed: 0.18, green: 0.62, blue: 0.98, alpha: 1.0)
        }
    }

    static let allFileActions: [ConversionFanAction] = [
        .float,
        .airDrop,
        .copy,
        .move,
        .copyPath,
        .openTerminal,
    ]

    /// Resolves valid actions for the given URLs and fan mode (matching Tangerine's validActions logic).
    static func validActions(for urls: [URL], mode: ConversionFanMode) -> [ConversionFanAction] {
        switch mode {
        case .fileActions:
            return allFileActions

        case .fileTools:
            if urls.isEmpty {
                // Default showcase tools when opened without files staged
                return [
                    .fileTool(.compress),
                    .fileTool(.removeMetadata),
                    .fileTool(.editImage),
                    .fileTool(.frameImage),
                    .fileTool(.cropImage),
                    .fileTool(.annotateImage),
                    .fileTool(.createCollage),
                    .fileTool(.readQRCode),
                    .fileTool(.redactImage),
                    .fileTool(.trimVideo),
                    .fileTool(.normalizeAudio),
                    .fileTool(.extractArchive),
                ]
            }
            return FileTool.allCases.filter { $0.supports(urls: urls) }.map { .fileTool($0) }

        case .conversions:
            if urls.isEmpty {
                return [
                    .convert(.webp),
                    .convert(.jpg),
                    .convert(.png),
                    .convert(.heic),
                    .convert(.pdf),
                    .convert(.gif),
                    .convert(.mp4),
                    .convert(.mp3),
                    .convert(.wav),
                    .convert(.zip),
                ]
            }
            // Folders, alone or mixed with files, can only be archived
            let anyDir = urls.contains { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
            if anyDir {
                return [.convert(.zip), .convert(.tar), .convert(.gz)]
            }

            let detected = urls.compactMap { ConversionFormat.detect(for: $0) }
            guard detected.count == urls.count, let first = detected.first else {
                return []
            }
            var common = first.supportedOutputs
            for format in detected.dropFirst() {
                let set = Set(format.supportedOutputs)
                common.removeAll { !set.contains($0) }
            }
            // Also always allow bundling multiple files into ZIP
            if urls.count > 1 && !common.contains(.zip) {
                common.append(.zip)
            }
            return common.map { .convert($0) }
        }
    }
}

/// Legacy alias for compatibility with callers.
typealias ConversionTarget = ConversionFanAction

// MARK: - Tool Options Models (matching Tangerine's FileToolOptions)

enum CompressionTargetMode: String, CaseIterable, Identifiable {
    case preset
    case percentage
    case fileSize

    var id: String { rawValue }
    var title: String {
        switch self {
        case .preset: return "Preset"
        case .percentage: return "Reduction %"
        case .fileSize: return "Target Size (KB)"
        }
    }
}

enum FrameBackgroundPreset: String, CaseIterable, Identifiable {
    case citrus
    case sunset
    case meadow
    case oasis
    case lagoon
    case orchid
    case violet
    case graphite
    case white
    case black

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colors: (NSColor, NSColor) {
        switch self {
        case .citrus:
            return (NSColor(srgbRed: 1.0, green: 0.42, blue: 0.05, alpha: 1), NSColor(srgbRed: 1.0, green: 0.78, blue: 0.14, alpha: 1))
        case .sunset:
            return (NSColor(srgbRed: 0.96, green: 0.24, blue: 0.42, alpha: 1), NSColor(srgbRed: 0.99, green: 0.58, blue: 0.20, alpha: 1))
        case .meadow:
            return (NSColor(srgbRed: 0.16, green: 0.78, blue: 0.44, alpha: 1), NSColor(srgbRed: 0.62, green: 0.92, blue: 0.32, alpha: 1))
        case .oasis:
            return (NSColor(srgbRed: 0.08, green: 0.68, blue: 0.78, alpha: 1), NSColor(srgbRed: 0.24, green: 0.88, blue: 0.64, alpha: 1))
        case .lagoon:
            return (NSColor(srgbRed: 0.14, green: 0.40, blue: 0.92, alpha: 1), NSColor(srgbRed: 0.20, green: 0.78, blue: 0.96, alpha: 1))
        case .orchid:
            return (NSColor(srgbRed: 0.82, green: 0.28, blue: 0.86, alpha: 1), NSColor(srgbRed: 0.98, green: 0.48, blue: 0.66, alpha: 1))
        case .violet:
            return (NSColor(srgbRed: 0.42, green: 0.20, blue: 0.90, alpha: 1), NSColor(srgbRed: 0.72, green: 0.38, blue: 0.98, alpha: 1))
        case .graphite:
            return (NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1), NSColor(srgbRed: 0.28, green: 0.30, blue: 0.35, alpha: 1))
        case .white:
            return (NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.90, green: 0.91, blue: 0.94, alpha: 1))
        case .black:
            return (NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1), NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1))
        }
    }
}

enum FrameCanvasRatio: String, CaseIterable, Identifiable {
    case automatic
    case square
    case landscape
    case portrait

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .square: return "Square · 1:1"
        case .landscape: return "Landscape · 16:9"
        case .portrait: return "Portrait · 4:5"
        }
    }
}

struct FrameImageOptions: Equatable {
    var background: FrameBackgroundPreset = .citrus
    var padding: Double = 48
    var cornerRadius: Double = 18
    var shadowRadius: Double = 24
    var canvasRatio: FrameCanvasRatio = .automatic
}

struct ImageAdjustments: Equatable {
    var exposure: Double = 0.0      // -2.0 ... 2.0
    var brightness: Double = 0.0    // -0.5 ... 0.5
    var contrast: Double = 1.0      // 0.5 ... 1.5
    var saturation: Double = 1.0    // 0.0 ... 2.0
    var temperature: Double = 6500  // 3500 ... 9500
    var sharpness: Double = 0.0     // 0.0 ... 2.0
    var vignette: Double = 0.0      // 0.0 ... 2.0
    var blur: Double = 0.0          // 0.0 ... 20.0
}

enum AnnotationKind: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case ellipse
    case highlighter
    case text
    case number
    case magnifier

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .number: return "1.circle.fill"
        case .magnifier: return "plus.magnifyingglass"
        }
    }
}

struct ImageAnnotation: Identifiable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    /// Normalized coordinates in 0...1 (origin bottom-left or top-left)
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double
    var text: String = "Note"
    var number: Int = 1
    var color: NSColor = NSColor(srgbRed: 1.0, green: 0.32, blue: 0.0, alpha: 1.0)
    var lineWidth: Double = 4.0
    var magnification: Double = 2.0

    init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        text: String = "Note",
        number: Int = 1,
        color: NSColor = NSColor(srgbRed: 1.0, green: 0.32, blue: 0.0, alpha: 1.0),
        lineWidth: Double = 4.0,
        magnification: Double = 2.0
    ) {
        self.id = id
        self.kind = kind
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.text = text
        self.number = number
        self.color = color
        self.lineWidth = lineWidth
        self.magnification = magnification
    }
}

enum CollageStyle: String, CaseIterable, Identifiable {
    case grid
    case horizontal
    case vertical
    case featured

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CollageBackground: String, CaseIterable, Identifiable {
    case white
    case black
    case transparent

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct CollageOptions: Equatable {
    var style: CollageStyle = .grid
    var columns: Int = 2
    var width: Int = 1920
    var spacing: Double = 16
    var padding: Double = 24
    var cornerRadius: Double = 14
    var background: CollageBackground = .white
}

enum RedactionStyle: String, CaseIterable, Identifiable {
    case blur
    case solid

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct RedactionRectangle: Identifiable, Equatable {
    let id: UUID
    /// Normalized 0...1 coordinates in image space (origin bottom-left)
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(id: UUID = UUID(), x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct FileToolOptions {
    // Compression
    var compressionTargetMode: CompressionTargetMode = .preset
    var compressionReductionPercentage: Double = 50 // 1...99%
    var targetSizeKB: Int = 500
    var imageCompression: ImageCompressionOptions = AppSettings.shared.imageCompressionOptions
    var videoCompression: VideoCompressionOptions = AppSettings.shared.videoCompressionOptions

    // Image Tools
    var imageAdjustments: ImageAdjustments = ImageAdjustments()
    var imageFrame: FrameImageOptions = FrameImageOptions()
    var annotations: [ImageAnnotation] = []
    var collage: CollageOptions = CollageOptions()
    var redactionStyle: RedactionStyle = .blur
    var redactions: [RedactionRectangle] = []

    // Crop (normalized 0...1, origin top-left of the upright image/frame)
    var cropX: Double = 0.05
    var cropY: Double = 0.05
    var cropWidth: Double = 0.90
    var cropHeight: Double = 0.90

    // Audio / Video Tools
    var trimStartSeconds: Double = 0.0
    var trimDurationSeconds: Double = 10.0
    var autoTrimSilence: Bool = false
    var silenceThresholdDB: Double = -45.0
    var playbackSpeed: Double = 1.5
    var normalizationTargetLoudness: Double = -16.0
    var normalizationLoudnessRange: Double = 11.0
    var normalizationTruePeak: Double = -1.5
    var audioChannelCount: Int = 2 // 1 = Mono, 2 = Stereo
    var audioLeftVolume: Double = 1.0
    var audioRightVolume: Double = 1.0
    var visualizerColorHex: String = "0xff5200"

    // PDF Organize
    var pdfPageOrder: [Int] = []
    var pdfPageRotations: [Int: Int] = [:]
}
