// Daisy — probes media files with ffprobe and reports which ffmpeg encoders are available.
import Foundation

struct MediaInfo {
    let duration: Double
    let hasVideo: Bool
    let hasAudio: Bool
    let width: Int?
    let height: Int?
    let frameRate: Double?
    let audioCodec: String?
    let audioSampleRate: Int?
    let audioChannels: Int?
    let audioBitsPerSample: Int?
    let audioIsFloat: Bool
}

enum MediaProbe {
    private static let encoderLock = NSLock()
    private static var encoderNames: Set<String>?

    /// Reads container and stream facts via ffprobe JSON. Returns nil when ffprobe is missing or the file is unreadable.
    static func probe(_ url: URL) -> MediaInfo? {
        let ffprobe = ToolLocator.ffprobe()
        guard !ffprobe.isEmpty else { return nil }
        let res = ToolRunner.run(
            ffprobe,
            arguments: ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path],
            timeout: 60
        )
        guard res.succeeded,
              let data = res.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let format = root["format"] as? [String: Any] ?? [:]
        let streams = root["streams"] as? [[String: Any]] ?? []
        // Cover art (attached pictures) is reported as a video stream but is not video content.
        let video = streams.first {
            $0["codec_type"] as? String == "video"
                && ($0["disposition"] as? [String: Any])?["attached_pic"] as? Int != 1
        }
        let audio = streams.first { $0["codec_type"] as? String == "audio" }

        let duration = Double(format["duration"] as? String ?? "")
            ?? Double(video?["duration"] as? String ?? "")
            ?? 0

        let audioCodec = audio?["codec_name"] as? String
        // Bit depth and float-ness only mean something for PCM/FLAC sources; lossy codecs decode to float internally.
        let losslessAudio = audioCodec.map { $0.hasPrefix("pcm_") || $0 == "flac" } ?? false
        let sampleFormat = audio?["sample_fmt"] as? String ?? ""
        let isFloat = losslessAudio && (sampleFormat.hasPrefix("flt") || sampleFormat.hasPrefix("dbl"))
        var bits: Int?
        if losslessAudio {
            bits = Int(audio?["bits_per_raw_sample"] as? String ?? "")
                ?? Int(sampleFormat.filter(\.isNumber))
            if bits == nil, isFloat { bits = 32 }
        }

        return MediaInfo(
            duration: duration,
            hasVideo: video != nil,
            hasAudio: audio != nil,
            width: video?["width"] as? Int,
            height: video?["height"] as? Int,
            frameRate: frameRate(video?["avg_frame_rate"] as? String) ?? frameRate(video?["r_frame_rate"] as? String),
            audioCodec: audioCodec,
            audioSampleRate: Int(audio?["sample_rate"] as? String ?? ""),
            audioChannels: audio?["channels"] as? Int,
            audioBitsPerSample: bits,
            audioIsFloat: isFloat
        )
    }

    /// True when the ffmpeg build ships the named encoder. The encoder list is read once and cached.
    static func hasEncoder(_ name: String) -> Bool {
        encoderLock.lock()
        defer { encoderLock.unlock() }
        if encoderNames == nil {
            let ffmpeg = ToolLocator.ffmpeg()
            guard !ffmpeg.isEmpty else { return false }
            let res = ToolRunner.run(ffmpeg, arguments: ["-hide_banner", "-encoders"], timeout: 30)
            guard res.succeeded else { return false }
            // Encoder rows look like " V....D libx264  H.264 ...": a 6-character flag field, then the name.
            encoderNames = Set(res.stdout.components(separatedBy: .newlines).compactMap { line in
                let parts = line.split(separator: " ")
                guard parts.count >= 2, parts[0].count == 6 else { return nil }
                return String(parts[1])
            })
        }
        return encoderNames?.contains(name) ?? false
    }

    /// PCM codec name for WAV/AIFF output. `.matchSource` follows the source's bit depth; lossy sources get 16-bit.
    static func pcmCodec(depth: AudioSampleDepth, source: MediaInfo?, bigEndian: Bool) -> String {
        let resolved: AudioSampleDepth
        if depth == .matchSource {
            if source?.audioIsFloat == true {
                resolved = .float32
            } else {
                switch source?.audioBitsPerSample ?? 16 {
                case 24: resolved = .bit24
                case 32: resolved = .bit32
                default: resolved = .bit16
                }
            }
        } else {
            resolved = depth
        }
        switch resolved {
        case .bit24: return bigEndian ? "pcm_s24be" : "pcm_s24le"
        case .bit32: return bigEndian ? "pcm_s32be" : "pcm_s32le"
        case .float32: return bigEndian ? "pcm_f32be" : "pcm_f32le"
        case .matchSource, .bit16: return bigEndian ? "pcm_s16be" : "pcm_s16le"
        }
    }

    /// Audio codec arguments for an output with the given extension, keeping the source's codec family.
    /// Returns `[]` for unknown extensions so ffmpeg picks its default, and nil when the container's encoder is missing.
    static func audioEncoderArgs(forExtension ext: String, source: MediaInfo?) -> [String]? {
        let codec: String
        switch ext.lowercased() {
        case "mp3":
            codec = "libmp3lame"
        case "m4a", "mp4", "mov", "aac":
            codec = "aac"
        case "ogg", "oga":
            guard let encoder = oggEncoder() else { return nil }
            codec = encoder
        case "opus", "webm", "mkv":
            codec = "libopus"
        case "flac":
            codec = "flac"
        case "wav":
            codec = pcmCodec(depth: .matchSource, source: source, bigEndian: false)
        case "aiff", "aif":
            codec = pcmCodec(depth: .matchSource, source: source, bigEndian: true)
        default:
            return []
        }
        return ["-c:a", codec]
    }

    /// libvorbis when built in, otherwise libopus inside the Ogg container; nil when neither exists.
    static func oggEncoder() -> String? {
        if hasEncoder("libvorbis") { return "libvorbis" }
        if hasEncoder("libopus") { return "libopus" }
        return nil
    }

    private static func frameRate(_ fraction: String?) -> Double? {
        guard let fraction else { return nil }
        let parts = fraction.split(separator: "/").compactMap { Double($0) }
        let value: Double?
        if parts.count == 2 {
            value = parts[1] > 0 ? parts[0] / parts[1] : nil
        } else {
            value = parts.first
        }
        return value.flatMap { $0 > 0 ? $0 : nil }
    }
}
