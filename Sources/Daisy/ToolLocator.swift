// Daisy — locates external tools the user can override in Settings.
import Foundation

enum ToolLocator {
    static let candidatePrefixes = ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"]

    static func openAt(_ custom: String, _ name: String) -> String {
        if !custom.isEmpty, FileManager.default.isExecutableFile(atPath: custom) { return custom }
        for prefix in candidatePrefixes {
            let path = prefix + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return custom
    }

    static func ffmpeg(_ s: AppSettings) -> String { openAt(s.ffmpegPath, "ffmpeg") }
    static func cwebp(_ s: AppSettings) -> String { openAt(s.cwebpPath, "cwebp") }
    static func exiftool(_ s: AppSettings) -> String { openAt(s.exiftoolPath, "exiftool") }

    static func toolStatus(_ s: AppSettings) -> [(name: String, found: Bool)] {
        [
            ("ffmpeg", !ffmpeg(s).isEmpty && FileManager.default.isExecutableFile(atPath: ffmpeg(s))),
            ("cwebp", !cwebp(s).isEmpty && FileManager.default.isExecutableFile(atPath: cwebp(s))),
            ("exiftool", !exiftool(s).isEmpty && FileManager.default.isExecutableFile(atPath: exiftool(s))),
        ]
    }
}
