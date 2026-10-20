// Daisy — executes conversions using external tools and system frameworks.
import AppKit
import Foundation

final class ConversionEngine {
    private let settings: AppSettings
    private let queue = DispatchQueue(label: "daisy.engine", qos: .userInitiated)

    init(settings: AppSettings) {
        self.settings = settings
    }

    struct ConversionError: Error, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let message: String
        init(_ message: String) { self.message = message }
        init(stringLiteral value: String) { self.message = value }
    }

    enum Outcome {
        case success([URL])
        case failure(String)
    }

    /// Converts the given files for one target. Called on the engine queue.
    func convert(files: [URL], target: ConversionTarget) -> Outcome {
        var produced: [URL] = []
        var errors: [String] = []

        for file in files {
            let outcome: Result<URL, ConversionError>
            switch target.kind {
            case .webp:
                outcome = convertToWebP(file: file)
            case .image(let format):
                outcome = convertImage(file: file, format: format)
            case .audioVideo(let format):
                outcome = convertWithFfmpeg(file: file, format: format)
            case .stripMetadata:
                outcome = stripMetadata(file: file)
            case .copyToClipboard:
                outcome = copyToClipboard(file: file)
            case .revealInFinder:
                outcome = reveal(file: file)
            }

            switch outcome {
            case .success(let url): produced.append(url)
            case .failure(let message): errors.append("\(file.lastPathComponent): \(message)")
            }
        }

        if produced.isEmpty {
            return .failure(errors.joined(separator: "\n"))
        }
        if errors.isEmpty {
            return .success(produced)
        }
        return .failure("\(produced.count) converted, \(errors.count) failed.\n" + errors.joined(separator: "\n"))
    }

    // MARK: - WebP (cwebp)

    private func convertToWebP(file: URL) -> Result<URL, ConversionError> {
        let tool = ToolLocator.cwebp(settings)
        guard !tool.isEmpty else { return .failure("cwebp not installed. Run: brew install webp") }
        let out = outputURL(for: file, ext: "webp")
        let result = ToolRunner.run(
            tool, arguments: [file.path, "-o", out.path], timeout: Double(settings.timeoutSeconds)
        )
        guard result.succeeded else { return .failure(ConversionError(result.stderr.isEmpty ? "cwebp failed" : result.stderr)) }
        return .success(out)
    }

    // MARK: - Images via system frameworks / ImageIO

    private func convertImage(file: URL, format: ImageFormat) -> Result<URL, ConversionError> {
        guard let image = NSImage(contentsOf: file),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return .failure("Not readable as an image.") }

        let out = outputURL(for: file, ext: format.fileExtension)
        let utType: String
        switch format {
        case .jpeg: utType = "public.jpeg"
        case .png: utType = "public.png"
        case .heic: utType = "public.heic"
        }

        // JPEG cannot carry alpha; flatten onto white for that format.
        var source = cgImage
        if format == .jpeg && cgImage.hasAlpha {
            let width = cgImage.width, height = cgImage.height
            guard let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return .failure("Could not flatten image.") }
            ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 1, 1, 1])!)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let flattened = ctx.makeImage() else { return .failure("Could not flatten image.") }
            source = flattened
        }

        let destination = CGImageDestinationCreateWithURL(out as CFURL, utType as CFString, 1, nil)
        guard destination != nil else { return .failure("Could not create \(utType) encoder.") }
        CGImageDestinationAddImage(destination!, source as CGImage, nil)
        guard CGImageDestinationFinalize(destination!) else {
            return .failure("Encoding to \(utType) failed.")
        }
        return .success(out)
    }

    // MARK: - ffmpeg (audio/video)

    private func convertWithFfmpeg(file: URL, format: AVFormat) -> Result<URL, ConversionError> {
        let tool = ToolLocator.ffmpeg(settings)
        guard !tool.isEmpty else { return .failure("ffmpeg not installed. Run: brew install ffmpeg") }
        let out = outputURL(for: file, ext: format.fileExtension)
        let args = ffmpegArgs(input: file, output: out, format: format)
        let result = ToolRunner.run(
            tool, arguments: args, timeout: Double(settings.timeoutSeconds)
        )
        guard result.succeeded else {
            return .failure(ConversionError(result.stderr.isEmpty ? "conversion failed" : result.stderr))
        }
        return .success(out)
    }

    private func ffmpegArgs(input: URL, output: URL, format: AVFormat) -> [String] {
        switch format {
        case .gif:
            return ["-y", "-i", input.path, "-loop", "0", "-vf", "fps=12,scale=640:-1:flags=lanczos", output.path]
        case .mp4:
            return ["-y", "-i", input.path, "-c:v", "libx264", "-preset", "medium", "-c:a", "aac", output.path]
        case .mp3:
            return ["-y", "-i", input.path, "-vn", "-c:a", "libmp3lame", "-q:a", "2", output.path]
        case .wav:
            return ["-y", "-i", input.path, "-vn", output.path]
        }
    }

    // MARK: - Metadata (exiftool; Daisy does not bundle GPL tools)

    private func stripMetadata(file: URL) -> Result<URL, ConversionError> {
        let tool = ToolLocator.exiftool(settings)
        guard !tool.isEmpty else { return .failure("exiftool not installed. Run: brew install exiftool") }
        let out = outputURL(for: file, ext: file.pathExtension.isEmpty ? "out" : file.pathExtension)
        let result = ToolRunner.run(
            tool, arguments: ["-all=", "-o", out.path, file.path], timeout: Double(settings.timeoutSeconds)
        )
        guard result.succeeded else { return .failure(ConversionError(result.stderr)) }
        return .success(out)
    }

    // MARK: - Clipboard / Finder actions

    private func copyToClipboard(file: URL) -> Result<URL, ConversionError> {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([file as NSURL])
        return .success(file)
    }

    private func reveal(file: URL) -> Result<URL, ConversionError> {
        NSWorkspace.shared.activateFileViewerSelecting([file])
        return .success(file)
    }

    // MARK: - Output naming

    func outputURL(for file: URL, ext: String, forceUnique: Bool = false) -> URL {
        let baseDir: URL
        if !settings.outputDirectory.isEmpty {
            baseDir = URL(fileURLWithPath: settings.outputDirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } else {
            baseDir = file.deletingLastPathComponent()
        }
        let stem = file.deletingPathExtension().lastPathComponent
        var candidate = baseDir
            .appendingPathComponent(stem)
            .appendingPathExtension(ext)
        if forceUnique {
            candidate = uniqueURL(candidate)
        } else {
            let exists = FileManager.default.fileExists(atPath: candidate.path)
            if exists { candidate = uniqueURL(candidate) }
        }
        return candidate
    }

    private func uniqueURL(_ url: URL) -> URL {
        var url = url
        var index = 1
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        while FileManager.default.fileExists(atPath: url.path) {
            url = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-\(index)")
                .appendingPathExtension(ext)
            index += 1
        }
        return url
    }
}

extension CGImage {
    var hasAlpha: Bool {
        alphaInfo != .none && alphaInfo != .noneSkipLast && alphaInfo != .noneSkipFirst
    }
}
