// Daisy — the conversion targets (fan petals) the app offers.
import Foundation

struct ConversionTarget: Identifiable {
    enum Kind {
        case image(format: ImageFormat)
        case audioVideo(format: AVFormat)
        case webp
        case stripMetadata
        case copyToClipboard
        case revealInFinder
    }

    let kind: Kind
    let label: String

    var id: String { label }

    static let fan: [ConversionTarget] = [
        ConversionTarget(kind: .webp, label: "WebP"),
        ConversionTarget(kind: .image(format: .jpeg), label: "JPEG"),
        ConversionTarget(kind: .image(format: .png), label: "PNG"),
        ConversionTarget(kind: .image(format: .heic), label: "HEIC"),
        ConversionTarget(kind: .audioVideo(format: .gif), label: "GIF"),
        ConversionTarget(kind: .audioVideo(format: .mp4), label: "MP4"),
        ConversionTarget(kind: .audioVideo(format: .mp3), label: "MP3"),
        ConversionTarget(kind: .audioVideo(format: .wav), label: "WAV"),
        ConversionTarget(kind: .stripMetadata, label: "Strip Meta"),
        ConversionTarget(kind: .copyToClipboard, label: "Copy"),
        ConversionTarget(kind: .revealInFinder, label: "Reveal"),
    ]
}

enum ImageFormat {
    case jpeg
    case png
    case heic

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        }
    }
}

enum AVFormat {
    case gif
    case mp4
    case mp3
    case wav

    var fileExtension: String {
        switch self {
        case .gif: return "gif"
        case .mp4: return "mp4"
        case .mp3: return "mp3"
        case .wav: return "wav"
        }
    }
}
