// Daisy — user-configurable settings stored in UserDefaults.
import Foundation

final class AppSettings {
    static var shared = AppSettings()

    /// Path to the ffmpeg binary. Empty = automatic lookup.
    var ffmpegPath: String {
        didSet { save("ffmpegPath", ffmpegPath) }
    }
    /// Path to the cwebp binary (WebP encoder).
    var cwebpPath: String {
        didSet { save("cwebpPath", cwebpPath) }
    }
    /// Path to the exiftool binary (metadata tools).
    var exiftoolPath: String {
        didSet { save("exiftoolPath", exiftoolPath) }
    }
    /// Where converted files are written. Empty = alongside the source file.
    var outputDirectory: String {
        didSet { save("outputDirectory", outputDirectory) }
    }
    /// Per-file conversion timeout in seconds.
    var timeoutSeconds: Int {
        didSet { UserDefaults.standard.set(timeoutSeconds, forKey: "timeoutSeconds") }
    }

    init() {
        let d = UserDefaults.standard
        ffmpegPath = d.string(forKey: "ffmpegPath") ?? ""
        cwebpPath = d.string(forKey: "cwebpPath") ?? ""
        exiftoolPath = d.string(forKey: "exiftoolPath") ?? ""
        outputDirectory = d.string(forKey: "outputDirectory") ?? ""
        timeoutSeconds = d.object(forKey: "timeoutSeconds") as? Int ?? 300
    }

    private func save(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Notification.Name {
    static let daisyOpenSettings = Notification.Name("daisy.openSettings")
}
