// Daisy — locates external and system tools (bundled, Homebrew, or custom path in Settings).
import Foundation

enum ToolLocator {
    static let candidatePrefixes = [
        "/opt/homebrew/bin/",
        "/usr/local/bin/",
        "/usr/bin/",
        "/bin/",
    ]

    /// Returns the expanded path of a user-supplied tool path when it is an existing, non-directory, executable file.
    private static func normalized(_ custom: String) -> String? {
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let path = (trimmed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    static func openAt(_ custom: String, _ name: String) -> String {
        if let path = normalized(custom) {
            return path
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tools/\(name)").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        if name == "exiftool",
           let bundledExif = Bundle.main.resourceURL?.appendingPathComponent("ExifTool/exiftool").path,
           FileManager.default.isExecutableFile(atPath: bundledExif) {
            return bundledExif
        }
        for prefix in candidatePrefixes {
            let path = prefix + name
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return ""
    }

    static func ffmpeg(_ s: AppSettings = .shared) -> String { openAt(s.ffmpegPath, "ffmpeg") }
    static func ffprobe(_ s: AppSettings = .shared) -> String {
        if let custom = normalized(s.ffmpegPath) {
            let sibling = URL(fileURLWithPath: custom).deletingLastPathComponent().appendingPathComponent("ffprobe").path
            if let found = normalized(sibling) { return found }
        }
        return openAt("", "ffprobe")
    }
    static func cwebp(_ s: AppSettings = .shared) -> String { openAt(s.cwebpPath, "cwebp") }
    static func dwebp(_ s: AppSettings = .shared) -> String {
        if let custom = normalized(s.cwebpPath) {
            let sibling = URL(fileURLWithPath: custom).deletingLastPathComponent().appendingPathComponent("dwebp").path
            if let found = normalized(sibling) { return found }
        }
        return openAt("", "dwebp")
    }
    static func exiftool(_ s: AppSettings = .shared) -> String { openAt(s.exiftoolPath, "exiftool") }

    static func toolStatus(_ s: AppSettings = .shared) -> [(name: String, path: String, found: Bool)] {
        let f = ffmpeg(s)
        let c = cwebp(s)
        let e = exiftool(s)
        return [
            ("ffmpeg", f, !f.isEmpty),
            ("cwebp", c, !c.isEmpty),
            ("exiftool", e, !e.isEmpty),
        ]
    }
}
