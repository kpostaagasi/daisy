// Daisy — complete conversion and file-tool engine inspired by Tangerine.
import AppKit
import AVFoundation
import CoreImage
import Foundation
import PDFKit
import Quartz

final class ConversionEngine {
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    struct ConversionError: Error, LocalizedError, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let message: String
        init(_ message: String) { self.message = message }
        init(stringLiteral value: String) { self.message = value }
        var errorDescription: String? { message }
    }

    enum Outcome {
        case success([URL])
        case failure(String)
    }

    // MARK: - Top-level Dispatch

    func convert(
        files: [URL],
        format: ConversionFormat,
        progress: ((Int, Int, String) -> Void)? = nil
    ) -> Outcome {
        guard !files.isEmpty else { return .failure("Drop at least one item.") }

        // Multi-file archive bundle (when multiple files or a folder are converted to ZIP/TAR/GZ)
        if [.zip, .tar, .gz].contains(format) && (files.count > 1 || isDirectory(files[0])) {
            progress?(1, 1, files[0].lastPathComponent)
            switch createArchive(from: files, format: format) {
            case .success(let url): return .success([url])
            case .failure(let err): return .failure(err.message)
            }
        }

        let opts = settings.options(for: format)
        var produced: [URL] = []
        var errors: [String] = []

        for (idx, file) in files.enumerated() {
            progress?(idx + 1, files.count, file.lastPathComponent)
            let result = convertSingleFile(file, to: format, options: opts)
            switch result {
            case .success(let urls):
                produced.append(contentsOf: urls)
            case .failure(let err):
                errors.append("\(file.lastPathComponent): \(err.message)")
            }
        }

        return summarize(produced: produced, errors: errors)
    }

    func runTool(
        files: [URL],
        tool: FileTool,
        options: FileToolOptions = FileToolOptions(),
        progress: ((Int, Int, String) -> Void)? = nil
    ) -> Outcome {
        guard !files.isEmpty else { return .failure("Drop at least one item.") }
        guard tool.supports(urls: files) else {
            return .failure("\(tool.fullTitle) isn’t available for these files.")
        }

        // Multi-input tools that produce a single combined output
        switch tool {
        case .createCollage:
            progress?(1, 1, "Creating collage…")
            switch createCollage(from: files, options: options.collage) {
            case .success(let url): return .success([url])
            case .failure(let err): return .failure(err.message)
            }
        case .mergePDF:
            progress?(1, 1, "Merging PDFs…")
            switch mergePDFs(files) {
            case .success(let url): return .success([url])
            case .failure(let err): return .failure(err.message)
            }
        case .createPDF:
            progress?(1, 1, "Creating PDF…")
            switch createPDFFromImages(files) {
            case .success(let url): return .success([url])
            case .failure(let err): return .failure(err.message)
            }
        case .joinVideos:
            progress?(1, 1, "Joining videos…")
            switch joinVideos(files) {
            case .success(let url): return .success([url])
            case .failure(let err): return .failure(err.message)
            }
        default:
            break
        }

        var produced: [URL] = []
        var errors: [String] = []

        for (idx, file) in files.enumerated() {
            progress?(idx + 1, files.count, file.lastPathComponent)
            let res = runSingleFileTool(file: file, tool: tool, options: options)
            switch res {
            case .success(let urls):
                produced.append(contentsOf: urls)
            case .failure(let err):
                errors.append("\(file.lastPathComponent): \(err.message)")
            }
        }

        return summarize(produced: produced, errors: errors)
    }

    private func summarize(produced: [URL], errors: [String]) -> Outcome {
        if produced.isEmpty {
            return .failure(errors.isEmpty ? "The operation couldn’t be completed." : errors.joined(separator: "\n"))
        }
        if errors.isEmpty {
            return .success(produced)
        }
        return .failure("\(produced.count) completed, \(errors.count) failed.\n" + errors.joined(separator: "\n"))
    }

    // MARK: - Single File Format Conversion

    private func convertSingleFile(
        _ file: URL,
        to target: ConversionFormat,
        options: ConversionOptions
    ) -> Result<[URL], ConversionError> {
        let srcFormat = ConversionFormat.detect(for: file)

        switch srcFormat {
        case .csv?, .tsv?:
            if target == .pdf {
                return convertDocumentToPDF(file: file, sourceFormat: srcFormat).map { [$0] }
            }
            if [.csv, .tsv, .txt, .md, .html].contains(target) {
                return convertDelimitedTable(file: file, target: target).map { [$0] }
            }
        case .srt?, .vtt?:
            if [.srt, .vtt, .txt].contains(target) {
                return convertSubtitles(file: file, target: target).map { [$0] }
            }
        case .zip?, .tar?, .gz?:
            if [.zip, .tar, .gz].contains(target) {
                return repackArchive(file: file, format: target).map { [$0] }
            }
        default:
            break
        }

        switch target {
        case .webp, .jpg, .png, .heic, .tiff, .bmp:
            if srcFormat == .pdf {
                return renderPDFPagesToImages(file: file, format: target, options: options)
            }
            if target == .webp {
                return convertToWebP(file: file, options: options).map { [$0] }
            }
            return convertToSystemImage(file: file, format: target, options: options).map { [$0] }
        case .avif:
            return convertToAVIF(file: file, options: options).map { [$0] }
        case .pdf:
            if srcFormat?.group == .images {
                return createPDFFromImages([file]).map { [$0] }
            }
            return convertDocumentToPDF(file: file, sourceFormat: srcFormat).map { [$0] }
        case .txt, .md, .rtf, .html, .docx:
            return convertDocument(file: file, sourceFormat: srcFormat, target: target).map { [$0] }
        case .csv, .tsv:
            return convertDelimitedTable(file: file, target: target).map { [$0] }
        case .srt, .vtt:
            return convertSubtitles(file: file, target: target).map { [$0] }
        case .zip, .tar, .gz:
            return createArchive(from: [file], format: target).map { [$0] }
        case .gif where srcFormat?.group == .images && srcFormat != .gif:
            return convertToSystemImage(file: file, format: .gif, options: options).map { [$0] }
        case .gif, .mp4, .mov, .mkv, .webm, .avi, .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff:
            return convertWithFfmpeg(file: file, target: target, options: options).map { [$0] }
        default:
            return .failure("Conversion to \(target.title) is unavailable for this file.")
        }
    }

    // MARK: - Image Conversions (ImageIO / CoreGraphics / cwebp)

    private func convertToWebP(file: URL, options: ConversionOptions) -> Result<URL, ConversionError> {
        let cwebp = ToolLocator.cwebp(settings)
        guard !cwebp.isEmpty else {
            return .failure("cwebp is required for WebP. Run: brew install webp")
        }
        let out = outputURL(for: file, ext: "webp")
        let source = CGImageSourceCreateWithURL(file as CFURL, nil)
        if ConversionFormat.detect(for: file) == .gif, let source, CGImageSourceGetCount(source) > 1 {
            return .failure("Animated GIF to WebP isn’t supported.")
        }
        let orientation = (source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }?[kCGImagePropertyOrientation] as? Int) ?? 1
        // cwebp reads only these inputs directly; anything else is rasterized first.
        let cwebpReadable = ["png", "jpg", "jpeg", "tif", "tiff", "webp"].contains(file.pathExtension.lowercased())
        // cwebp writes EXIF orientation only with -metadata. Without it the pixels stay sensor-oriented, so rotate them upright first.
        if !cwebpReadable || (!options.preserveMetadata && orientation != 1) {
            guard let cgImage = loadCGImage(from: file) else {
                return .failure("The source image could not be read.")
            }
            return saveCGImage(cgImage, to: out, format: .webp, quality: CGFloat(options.quality.webpQuality) / 100)
        }
        var args = ["-q", String(options.quality.webpQuality)]
        if options.preserveMetadata {
            args.append(contentsOf: ["-metadata", "all"])
        }
        args.append(contentsOf: [file.path, "-o", out.path])
        let res = ToolRunner.run(cwebp, arguments: args, timeout: Double(settings.timeoutSeconds))
        guard res.succeeded else {
            let detail = lastErrorLine(res.stderr)
            return .failure(ConversionError(detail.isEmpty ? "WebP encoding failed." : detail))
        }
        return .success(out)
    }

    private func convertToSystemImage(
        file: URL,
        format: ConversionFormat,
        options: ConversionOptions,
        maxDimension: Int? = nil,
        customQuality: CGFloat? = nil,
        suffix: String = ""
    ) -> Result<URL, ConversionError> {
        guard var cgImage = loadCGImage(from: file) else {
            return .failure("The source image could not be read.")
        }

        if let maxDim = maxDimension, max(cgImage.width, cgImage.height) > maxDim {
            if let resized = resizeCGImage(cgImage, maxDimension: maxDim) {
                cgImage = resized
            }
        }

        guard let utType = imageUTType(for: format) else {
            return .failure("\(format.title) encoding is not available on this Mac.")
        }
        if (format == .jpg || format == .bmp) && cgImage.hasAlpha {
            if let flattened = flattenAlphaOntoWhite(cgImage) {
                cgImage = flattened
            }
        }

        var props: [CFString: Any] = [:]
        if format == .jpg || format == .heic {
            props[kCGImageDestinationLossyCompressionQuality] = customQuality ?? options.quality.imageCompressionQuality
        }
        if options.preserveMetadata,
           let src = CGImageSourceCreateWithURL(file as CFURL, nil),
           let meta = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            for (k, v) in meta where k != kCGImagePropertyOrientation {
                props[k] = v
            }
            // Pixels are already upright, so a copied TIFF orientation would rotate the image a second time.
            if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
        }

        let out = outputURL(for: file, ext: format.fileExtension, suffix: suffix, forceUnique: !suffix.isEmpty)
        return writeImage(cgImage, to: out, utType: utType, properties: props)
    }

    // MARK: - Audio & Video Conversions (ffmpeg)

    private func convertWithFfmpeg(
        file: URL,
        target: ConversionFormat,
        options: ConversionOptions
    ) -> Result<URL, ConversionError> {
        let tool = ToolLocator.ffmpeg(settings)
        guard !tool.isEmpty else {
            return .failure("ffmpeg is required for \(target.title) conversion. Run: brew install ffmpeg")
        }

        let out = outputURL(for: file, ext: target.fileExtension)
        var args: [String] = ["-y", "-i", file.path]

        if !options.preserveMetadata {
            args.append(contentsOf: ["-map_metadata", "-1"])
        }

        switch target {
        case .gif:
            let fps = max(5, min(50, options.gifFrameRate))
            let maxW = max(160, options.gifMaxWidth)
            // Tangerine's high-quality 2-pass palettegen/paletteuse filter graph (0x1001125)
            let filter = "fps=\(fps),scale='min(\(maxW)\\,iw)':-2:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
            args.append(contentsOf: ["-loop", "0", "-vf", filter, out.path])

        case .mp4, .mov, .mkv:
            if options.videoMaxHeight > 0 {
                args.append(contentsOf: ["-vf", "scale=-2:'min(\(options.videoMaxHeight)\\,ih)'"])
            }
            args.append(contentsOf: [
                "-c:v", "libx264",
                "-crf", String(options.quality.videoCRF),
                "-preset", "medium",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-b:a", "\(options.audioBitrate)k",
                out.path
            ])

        case .webm:
            args.append(contentsOf: [
                "-c:v", "libvpx-vp9",
                "-crf", String(options.quality.videoCRF + 6),
                "-b:v", "0",
                "-c:a", "libopus",
                "-b:a", "\(options.audioBitrate)k",
                out.path
            ])

        case .avi:
            args.append(contentsOf: ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", out.path])

        case .mp3:
            args.append(contentsOf: ["-vn", "-c:a", "libmp3lame", "-b:a", "\(options.audioBitrate)k", out.path])

        case .m4a:
            args.append(contentsOf: ["-vn", "-c:a", "aac", "-b:a", "\(options.audioBitrate)k", out.path])

        case .wav:
            let codec = MediaProbe.pcmCodec(
                depth: options.audioSampleDepth,
                source: MediaProbe.probe(file),
                bigEndian: false
            )
            args.append(contentsOf: ["-vn", "-c:a", codec, out.path])

        case .flac:
            args.append(contentsOf: ["-vn", "-c:a", "flac", out.path])

        case .ogg:
            guard let encoder = MediaProbe.oggEncoder() else {
                return .failure("Ogg output needs the libvorbis or libopus encoder, and this ffmpeg build has neither.")
            }
            args.append(contentsOf: ["-vn", "-c:a", encoder, "-b:a", "\(options.audioBitrate)k", out.path])

        case .opus:
            guard MediaProbe.hasEncoder("libopus") else {
                return .failure("Opus output needs the libopus encoder, which this ffmpeg build lacks.")
            }
            args.append(contentsOf: ["-vn", "-c:a", "libopus", "-b:a", "\(options.audioBitrate)k", out.path])

        case .aiff:
            let codec = MediaProbe.pcmCodec(
                depth: options.audioSampleDepth,
                source: MediaProbe.probe(file),
                bigEndian: true
            )
            args.append(contentsOf: ["-vn", "-c:a", codec, out.path])
        default:
            args.append(out.path)
        }

        let res = ToolRunner.run(tool, arguments: args, timeout: Double(settings.timeoutSeconds))
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "The conversion process failed." : lastErrorLine(res.stderr)))
        }
        return .success(out)
    }

    // MARK: - Documents, PDFs, Subtitles, Tables, Archives

    private func renderPDFPage(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let w = max(1, Int(box.width * scale))
        let h = max(1, Int(box.height * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// Renders every page: `<stem>.<ext>` for one page, `<stem>-page-NN.<ext>` for several.
    private func renderPDFPagesToImages(
        file: URL,
        format: ConversionFormat,
        options: ConversionOptions
    ) -> Result<[URL], ConversionError> {
        guard let doc = PDFDocument(url: file), doc.pageCount > 0 else {
            return .failure("This PDF cannot be read or is password-protected.")
        }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("daisy-pdf-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        if format == .webp {
            do {
                try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            } catch {
                return .failure("Could not prepare WebP output.")
            }
        }

        let stem = outputStem(of: file)
        let quality = options.quality.imageCompressionQuality
        var outputs: [URL] = []
        for idx in 0..<doc.pageCount {
            guard let page = doc.page(at: idx), let image = renderPDFPage(page) else {
                return .failure("Could not render PDF page \(idx + 1).")
            }
            let suffix = doc.pageCount > 1 ? String(format: "-page-%02d", idx + 1) : ""
            if format == .webp {
                let png = scratch.appendingPathComponent("\(stem)\(suffix).png")
                if case .failure(let err) = saveCGImage(image, to: png, format: .png, quality: quality) {
                    return .failure(err)
                }
                switch convertToWebP(file: png, options: options) {
                case .failure(let err):
                    return .failure(err)
                case .success(let webp):
                    guard settings.outputDirectory.isEmpty else {
                        outputs.append(webp)
                        continue
                    }
                    let dest = outputURL(for: file, ext: "webp", suffix: suffix)
                    do {
                        try fm.moveItem(at: webp, to: dest)
                    } catch {
                        return .failure("Could not place the WebP output.")
                    }
                    outputs.append(dest)
                }
            } else {
                let dest = outputURL(for: file, ext: format.fileExtension, suffix: suffix)
                switch saveCGImage(image, to: dest, format: format, quality: quality) {
                case .success(let url):
                    outputs.append(url)
                case .failure(let err):
                    return .failure(err)
                }
            }
        }
        return .success(outputs)
    }

    private func createPDFFromImages(_ files: [URL]) -> Result<URL, ConversionError> {
        let pdf = PDFDocument()
        for file in files {
            guard let img = NSImage(contentsOf: file),
                  let page = PDFPage(image: img)
            else {
                return .failure("Could not read image \(file.lastPathComponent).")
            }
            pdf.insert(page, at: pdf.pageCount)
        }
        let out = outputURL(for: files[0], ext: "pdf", suffix: files.count > 1 ? "-combined" : "")
        guard pdf.write(to: out) else {
            return .failure("PDFKit could not write the combined PDF.")
        }
        return .success(out)
    }

    private func convertDocumentToPDF(file: URL, sourceFormat: ConversionFormat?) -> Result<URL, ConversionError> {
        let attrStr: NSAttributedString
        switch loadDocumentContent(file: file, sourceFormat: sourceFormat) {
        case .success(let content):
            attrStr = content
        case .failure(let err):
            return .failure(err)
        }

        let out = outputURL(for: file, ext: "pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let margin: CGFloat = 54
        let printableRect = pageRect.insetBy(dx: margin, dy: margin)

        let pdfData = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return .failure("Could not create PDF context.") }

        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        var currentIndex = 0
        let totalLength = attrStr.length

        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: printableRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: currentIndex, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length == 0 { break }
            currentIndex += visibleRange.length
        } while currentIndex < totalLength

        ctx.closePDF()
        do {
            try pdfData.write(to: out, options: .atomic)
            return .success(out)
        } catch {
            return .failure("Could not save generated PDF.")
        }
    }

    private func convertDocument(
        file: URL,
        sourceFormat: ConversionFormat?,
        target: ConversionFormat
    ) -> Result<URL, ConversionError> {
        let attrStr: NSAttributedString
        switch loadDocumentContent(file: file, sourceFormat: sourceFormat) {
        case .success(let content):
            attrStr = content
        case .failure(let err):
            return .failure(err)
        }

        let out = outputURL(for: file, ext: target.fileExtension)
        let fullRange = NSRange(location: 0, length: attrStr.length)

        do {
            switch target {
            case .txt, .md:
                try attrStr.string.write(to: out, atomically: true, encoding: .utf8)
            case .rtf:
                let data = try attrStr.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                try data.write(to: out, options: .atomic)
            case .html:
                let data = try attrStr.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
                try data.write(to: out, options: .atomic)
            case .docx:
                let data = try attrStr.data(from: fullRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
                try data.write(to: out, options: .atomic)
            default:
                return .failure("Unsupported document output format.")
            }
            return .success(out)
        } catch {
            return .failure("Document conversion failed: \(error.localizedDescription)")
        }
    }

    private func loadDocumentContent(file: URL, sourceFormat: ConversionFormat?) -> Result<NSAttributedString, ConversionError> {
        switch sourceFormat {
        case .txt?, .md?:
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                return .failure("This file isn’t readable text.")
            }
            guard sourceFormat == .md else { return .success(plainAttributed(text)) }
            guard let rendered = renderMarkdown(text) else {
                return .failure("This Markdown file could not be parsed.")
            }
            return .success(rendered)
        case .pdf?:
            guard let doc = PDFDocument(url: file) else {
                return .failure("This PDF cannot be read.")
            }
            return .success(plainAttributed(doc.string ?? ""))
        default:
            if let loaded = try? NSAttributedString(url: file, options: [:], documentAttributes: nil) {
                return .success(loaded)
            }
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                return .success(plainAttributed(text))
            }
            return .failure("The source document could not be read.")
        }
    }

    private func plainAttributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
    }

    /// Renders Markdown with heading sizes, bullet list items, and inline emphasis, links and code.
    private func renderMarkdown(_ text: String) -> NSAttributedString? {
        guard let parsed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) else { return nil }

        let headingSizes: [Int: CGFloat] = [1: 24, 2: 20, 3: 16]
        let rendered = NSMutableAttributedString()
        var currentBlock: [Int]?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            var size: CGFloat = 12
            var weight: NSFont.Weight = .regular
            var monospace = false
            var isListItem = false
            for component in components {
                switch component.kind {
                case .header(let level):
                    size = headingSizes[level] ?? size
                    weight = .bold
                case .listItem:
                    isListItem = true
                case .codeBlock:
                    monospace = true
                default:
                    break
                }
            }
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.stronglyEmphasized) { weight = .bold }
            if inline.contains(.code) { monospace = true }
            var font = monospace
                ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight)
            if inline.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            if let link = run.link { attributes[.link] = link }

            let block = components.map(\.identity)
            if block != currentBlock {
                if currentBlock != nil { rendered.append(NSAttributedString(string: "\n")) }
                currentBlock = block
                if isListItem { rendered.append(NSAttributedString(string: "• ", attributes: attributes)) }
            }
            rendered.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return rendered
    }

    private func convertDelimitedTable(file: URL, target: ConversionFormat) -> Result<URL, ConversionError> {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else {
            return .failure("The spreadsheet file could not be read as UTF-8.")
        }
        let inSep: Character = file.pathExtension.lowercased() == "tsv" ? "\t" : ","
        let rows = parseDelimitedRows(raw, separator: inSep)

        let out = outputURL(for: file, ext: target.fileExtension)
        do {
            switch target {
            case .csv:
                let text = rows.map { row in row.map { csvField($0) }.joined(separator: ",") }.joined(separator: "\n")
                try text.write(to: out, atomically: true, encoding: .utf8)
            case .tsv, .txt:
                let text = rows.map { row in
                    row.map { singleLine($0).replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t")
                }.joined(separator: "\n")
                try text.write(to: out, atomically: true, encoding: .utf8)
            case .md:
                guard let first = rows.first else { return .failure("Table is empty.") }
                func markdownRow(_ row: [String]) -> String {
                    "| " + row.map { singleLine($0).replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
                }
                var lines = [markdownRow(first), "| " + first.map { _ in "---" }.joined(separator: " | ") + " |"]
                lines += rows.dropFirst().map { markdownRow($0) }
                try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
            case .html:
                var html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>table{border-collapse:collapse;font-family:-apple-system,sans-serif;font-size:13px}td,th{border:1px solid #ccc;padding:6px 10px}</style></head><body><table>\n"
                for (idx, row) in rows.enumerated() {
                    let tag = idx == 0 ? "th" : "td"
                    html += "<tr>" + row.map { "<\(tag)>\(htmlEscape($0))</\(tag)>" }.joined() + "</tr>\n"
                }
                html += "</table></body></html>"
                try html.write(to: out, atomically: true, encoding: .utf8)
            default:
                return .failure("Unsupported table conversion.")
            }
            return .success(out)
        } catch {
            return .failure("Failed to write converted table.")
        }
    }

    /// RFC 4180: quoted fields, `""` escapes, separators and newlines inside quotes, CRLF/LF/CR row ends.
    private func parseDelimitedRows(_ text: String, separator: Character) -> [[String]] {
        let chars = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case separator:
                    row.append(field)
                    field = ""
                case "\n", "\r", "\r\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func singleLine(_ value: String) -> String {
        value.components(separatedBy: .newlines).joined(separator: " ")
    }

    private func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Subtitle Converter (matching Tangerine's SubtitleConverter)

    private func convertSubtitles(file: URL, target: ConversionFormat) -> Result<URL, ConversionError> {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return .failure("The subtitle file is not valid UTF-8.")
        }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let nonCueBlocks: Set<String> = ["WEBVTT", "NOTE", "STYLE", "REGION"]
        var cues: [(start: String, end: String, body: String)] = []

        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let firstLine = lines.first,
                  !nonCueBlocks.contains(String(firstLine.prefix { !$0.isWhitespace }))
            else { continue }
            guard let arrowIdx = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[arrowIdx].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parts[0].split(whereSeparator: \.isWhitespace).first,
                  let end = parts[1].split(whereSeparator: \.isWhitespace).first
            else { continue }
            let body = lines[(arrowIdx + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            cues.append((start: String(start), end: String(end), body: body))
        }

        guard !cues.isEmpty else {
            return .failure("No valid subtitle cues were found.")
        }

        let out = outputURL(for: file, ext: target.fileExtension)
        let outputText: String
        switch target {
        case .srt, .vtt:
            var rendered = target == .vtt ? "WEBVTT\n\n" : ""
            for (idx, cue) in cues.enumerated() {
                let start = subtitleTimestamp(cue.start, forSRT: target == .srt)
                let end = subtitleTimestamp(cue.end, forSRT: target == .srt)
                rendered += "\(idx + 1)\n\(start) --> \(end)\n\(cue.body)\n\n"
            }
            outputText = rendered
        case .txt:
            outputText = cues.map(\.body).joined(separator: "\n")
        default:
            return .failure("Unsupported subtitle format.")
        }

        do {
            try outputText.write(to: out, atomically: true, encoding: .utf8)
            return .success(out)
        } catch {
            return .failure("Could not write subtitle file.")
        }
    }

    private func subtitleTimestamp(_ raw: String, forSRT: Bool) -> String {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        guard forSRT else { return normalized }
        let padded = normalized.filter { $0 == ":" }.count == 1 ? "00:" + normalized : normalized
        return padded.replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Archive Converter (matching Tangerine's ArchiveConverter)

    private func createArchive(from files: [URL], format: ConversionFormat) -> Result<URL, ConversionError> {
        let fm = FileManager.default
        for file in files where !fm.fileExists(atPath: file.path) {
            return .failure("\(file.lastPathComponent) could not be found.")
        }
        let first = files[0]
        let out = files.count == 1
            ? outputURL(for: first, ext: format.fileExtension)
            : outputURL(for: first.deletingLastPathComponent().appendingPathComponent("Archive"), ext: format.fileExtension)

        let parents = Set(files.map { $0.deletingLastPathComponent().standardizedFileURL.path })
        if parents.count == 1 {
            return writeArchive(names: files.map(\.lastPathComponent), in: first.deletingLastPathComponent(), to: out, format: format)
        }

        let staging = fm.temporaryDirectory.appendingPathComponent("daisy-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return .failure("Could not prepare the archive.")
        }
        var names: [String] = []
        for file in files {
            let base = file.deletingPathExtension().lastPathComponent
            let ext = file.pathExtension
            var name = file.lastPathComponent
            var index = 1
            while fm.fileExists(atPath: staging.appendingPathComponent(name).path) {
                name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
                index += 1
            }
            do {
                try fm.copyItem(at: file, to: staging.appendingPathComponent(name))
            } catch {
                return .failure("Could not copy \(file.lastPathComponent) for archiving.")
            }
            names.append(name)
        }
        return writeArchive(names: names, in: staging, to: out, format: format)
    }

    private func writeArchive(names: [String], in workDir: URL, to out: URL, format: ConversionFormat) -> Result<URL, ConversionError> {
        let timeout = Double(settings.timeoutSeconds)
        let res: ToolResult
        switch format {
        case .zip:
            res = ToolRunner.run("/usr/bin/zip", arguments: ["-r", "-q", out.path] + names, currentDirectory: workDir, timeout: timeout)
        case .tar:
            res = ToolRunner.run("/usr/bin/tar", arguments: ["-cf", out.path] + names, currentDirectory: workDir, timeout: timeout)
        case .gz:
            res = ToolRunner.run("/usr/bin/tar", arguments: ["-czf", out.path] + names, currentDirectory: workDir, timeout: timeout)
        default:
            return .failure("Unsupported archive format.")
        }
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Could not create the \(format.title) archive." : lastErrorLine(res.stderr)))
        }

        let listing: ToolResult
        if format == .zip {
            listing = ToolRunner.run("/usr/bin/unzip", arguments: ["-Z1", out.path], timeout: timeout)
        } else {
            listing = ToolRunner.run("/usr/bin/tar", arguments: [format == .tar ? "-tf" : "-tzf", out.path], timeout: timeout)
        }
        let members = listing.stdout.split(whereSeparator: \.isNewline).count
        guard listing.succeeded, members >= names.count else {
            try? FileManager.default.removeItem(at: out)
            return .failure("The \(format.title) archive is missing files.")
        }
        return .success(out)
    }

    private func repackArchive(file: URL, format: ConversionFormat) -> Result<URL, ConversionError> {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("daisy-repack-\(UUID().uuidString)", isDirectory: true)
        let contents = work.appendingPathComponent("contents", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        do {
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        } catch {
            return .failure("Could not prepare the archive.")
        }
        if case .failure(let err) = unpackArchive(file, into: contents) {
            return .failure(err)
        }
        let names = (try? fm.contentsOfDirectory(atPath: contents.path)) ?? []
        guard !names.isEmpty else { return .failure("The archive is empty.") }
        return writeArchive(names: names, in: contents, to: outputURL(for: file, ext: format.fileExtension), format: format)
    }

    private func unpackArchive(_ file: URL, into dir: URL) -> Result<Void, ConversionError> {
        let timeout = Double(settings.timeoutSeconds)
        let res = ConversionFormat.detect(for: file) == .zip
            ? ToolRunner.run("/usr/bin/ditto", arguments: ["-x", "-k", file.path, dir.path], timeout: timeout)
            : ToolRunner.run("/usr/bin/tar", arguments: ["-xf", file.path, "-C", dir.path], timeout: timeout)
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Could not extract archive." : lastErrorLine(res.stderr)))
        }
        return .success(())
    }

    private func extractArchive(file: URL) -> Result<[URL], ConversionError> {
        let fm = FileManager.default
        let outDir = outputURL(for: file, ext: "", suffix: "-extracted", forceUnique: true)
        do {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        } catch {
            return .failure("Could not create the extraction folder.")
        }
        if case .failure(let err) = unpackArchive(file, into: outDir) {
            try? fm.removeItem(at: outDir)
            return .failure(err)
        }
        return .success([outDir])
    }

    // MARK: - Single File Tool Dispatch

    private func runSingleFileTool(
        file: URL,
        tool: FileTool,
        options: FileToolOptions
    ) -> Result<[URL], ConversionError> {
        switch tool {
        case .compress:
            return compressFile(file: file, options: options).map { [$0] }
        case .removeMetadata:
            return stripMetadata(file: file).map { [$0] }
        case .editImage:
            return adjustImage(file: file, adjustments: options.imageAdjustments).map { [$0] }
        case .frameImage:
            return frameImage(file: file, options: options.imageFrame).map { [$0] }
        case .cropImage:
            return cropImage(file: file, options: options).map { [$0] }
        case .annotateImage:
            return annotateImage(file: file, annotations: options.annotations).map { [$0] }
        case .redactImage:
            return redactImage(file: file, rectangles: options.redactions, style: options.redactionStyle).map { [$0] }
        case .normalizeAudio:
            return normalizeAudio(file: file, options: options).map { [$0] }
        case .trimAudio:
            return trimMedia(file: file, options: options, isAudioOnly: true).map { [$0] }
        case .audioChannels:
            return convertAudioChannels(file: file, options: options).map { [$0] }
        case .audioToVideo:
            return createAudioVisualizer(file: file, options: options).map { [$0] }
        case .muteVideo:
            return muteVideo(file: file).map { [$0] }
        case .trimVideo:
            return trimMedia(file: file, options: options, isAudioOnly: false).map { [$0] }
        case .cropVideo:
            return cropVideo(file: file, options: options).map { [$0] }
        case .changeVideoSpeed:
            return changeVideoSpeed(file: file, speed: options.playbackSpeed).map { [$0] }
        case .videoSnapshots:
            return extractVideoSnapshots(file: file)
        case .splitPDF:
            return splitPDF(file: file)
        case .organizePDF:
            return organizePDF(file: file, options: options).map { [$0] }
        case .extractArchive:
            return extractArchive(file: file)
        default:
            return .failure("\(tool.fullTitle) is not supported for \(file.lastPathComponent).")
        }
    }

    // MARK: - File Tool Implementations

    private func compressFile(file: URL, options: FileToolOptions) -> Result<URL, ConversionError> {
        guard let fmt = ConversionFormat.detect(for: file) else {
            return .failure("Unsupported file type for compression.")
        }

        if fmt.group == .images {
            if fmt == .gif || fmt == .svg {
                return .failure("Compression isn’t supported for GIF/SVG.")
            }
            guard var image = loadCGImage(from: file) else {
                return .failure("The source image could not be read.")
            }
            if let maxDim = options.imageCompression.size.maxPixelDimension,
               max(image.width, image.height) > maxDim,
               let resized = resizeCGImage(image, maxDimension: maxDim) {
                image = resized
            }
            let outFmt: ConversionFormat
            switch fmt {
            case .jpg, .heic:
                outFmt = fmt
            case .webp:
                outFmt = .webp
            case .png, .tiff, .bmp:
                outFmt = (image.hasAlpha && hasTransparentPixels(image)) ? .png : .jpg
            default:
                return .failure("Compression isn’t supported for \(fmt.title).")
            }
            let out = outputURL(for: file, ext: outFmt.fileExtension, suffix: "-compressed", forceUnique: true)

            let produced: Result<URL, ConversionError>
            switch options.compressionTargetMode {
            case .preset:
                let quality: CGFloat = (options.imageCompression.strength == .strong) ? 0.52 : 0.74
                produced = saveCGImage(image, to: out, format: outFmt, quality: quality)
            case .percentage:
                let keepRatio = max(0.10, min(0.95, 1.0 - options.compressionReductionPercentage / 100.0))
                produced = saveCGImage(image, to: out, format: outFmt, quality: CGFloat(keepRatio * 0.85))
            case .fileSize:
                produced = compressToTarget(image, format: outFmt, targetBytes: max(1, options.targetSizeKB) * 1000, out: out)
            }
            guard case .success(let written) = produced else { return produced }
            // An output no smaller than the input is not a compression; remove it and say so.
            guard fileSize(of: written) < fileSize(of: file) else {
                try? FileManager.default.removeItem(at: written)
                return .failure("This image is already compact.")
            }
            return .success(written)
        }

        if fmt == .pdf {
            guard let doc = PDFDocument(url: file) else { return .failure("Could not read PDF.") }
            guard let filter = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")) else {
                return .failure("The PDF size-reduction filter is not available on this Mac.")
            }
            let out = outputURL(for: file, ext: "pdf", suffix: "-compressed", forceUnique: true)
            let writeOptions: [PDFDocumentWriteOption: Any] = [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]
            guard doc.write(to: out, withOptions: writeOptions) else { return .failure("Could not create the compressed PDF.") }
            guard fileSize(of: out) < fileSize(of: file) else {
                try? FileManager.default.removeItem(at: out)
                return .failure("This PDF is already compact.")
            }
            return .success(out)
        }

        if fmt.group == .video {
            let ff = ToolLocator.ffmpeg(settings)
            guard !ff.isEmpty else { return .failure("ffmpeg is required for video compression.") }
            let out = outputURL(for: file, ext: "mp4", suffix: "-compressed", forceUnique: true)
            let crf = (options.videoCompression.strength == .strong) ? "29" : "24"
            let res = ToolRunner.run(
                ff,
                arguments: ["-y", "-i", file.path, "-c:v", "libx264", "-crf", crf, "-preset", "medium", "-c:a", "aac", "-b:a", "128k", out.path],
                timeout: Double(settings.timeoutSeconds)
            )
            guard res.succeeded else {
                return .failure(ConversionError(res.stderr.isEmpty ? "Video compression failed." : lastErrorLine(res.stderr)))
            }
            return .success(out)
        }

        return .failure("Compression is unavailable for this file type.")
    }

    private func stripMetadata(file: URL) -> Result<URL, ConversionError> {
        let ext = file.pathExtension.isEmpty ? "out" : file.pathExtension
        let out = outputURL(for: file, ext: ext, suffix: "-clean", forceUnique: true)

        // 1. Try exiftool if installed
        let exif = ToolLocator.exiftool(settings)
        if !exif.isEmpty {
            let res = ToolRunner.run(
                exif,
                arguments: ["-all=", "-o", out.path, file.path],
                timeout: Double(settings.timeoutSeconds)
            )
            if res.succeeded { return .success(out) }
        }

        // 2. Native ImageIO strip for images: GIFs keep every frame; other formats take a lossless copy when verified, otherwise decode/re-encode
        if let fmt = ConversionFormat.detect(for: file), fmt.group == .images {
            if fmt == .gif { return stripGIFMetadata(file: file, out: out) }
            if losslessStripImage(file: file, format: fmt, out: out) { return .success(out) }
            if let cg = loadCGImage(from: file) {
                return reencodeWithoutMetadata(cg, format: fmt, inputBytes: fileSize(of: file), out: out)
            }
        }

        // 3. Native PDFKit metadata strip for PDFs
        if file.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: file) {
            doc.documentAttributes = [:]
            guard doc.write(to: out) else { return .failure("PDFKit could not write the cleaned PDF.") }
            return .success(out)
        }

        // 4. Audio/Video via ffmpeg -map_metadata -1
        let ff = ToolLocator.ffmpeg(settings)
        if !ff.isEmpty {
            let res = ToolRunner.run(
                ff,
                arguments: ["-y", "-i", file.path, "-map_metadata", "-1", "-c", "copy", out.path],
                timeout: Double(settings.timeoutSeconds)
            )
            if res.succeeded { return .success(out) }
        }

        return .failure("exiftool or supported format is required to strip metadata.")
    }

    /// Copies image data without decoding and drops identifying metadata. Returns false, leaving no output, unless the copy verifiably lacks it; the caller then re-encodes.
    private func losslessStripImage(file: URL, format: ConversionFormat, out: URL) -> Bool {
        guard [ConversionFormat.jpg, .heic, .png, .tiff].contains(format),
              let utType = imageUTType(for: format),
              let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let srcProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              (srcProps[kCGImagePropertyOrientation] as? Int ?? 1) == 1
        else { return false }

        // An empty metadata object drops all EXIF and XMP from JPEG copies. HEIC copies keep their raw EXIF block unless the identifying tags are removed from the source metadata, so that is the second candidate.
        let pruned = CGImageMetadataCreateMutableCopy(CGImageSourceCopyMetadataAtIndex(src, 0, nil) ?? CGImageMetadataCreateMutable()) ?? CGImageMetadataCreateMutable()
        let identifyingPaths = [
            "exif:GPSLatitude", "exif:GPSLongitude", "exif:GPSLatitudeRef", "exif:GPSLongitudeRef",
            "exif:GPSAltitude", "exif:GPSAltitudeRef", "exif:GPSTimeStamp", "exif:GPSDateStamp",
            "tiff:Make", "tiff:Model", "exif:DateTimeOriginal", "exif:DateTimeDigitized", "exif:DateTime",
            "exifEX:BodySerialNumber", "exifEX:LensModel", "exifEX:LensMake", "exifEX:CameraOwnerName",
            "exif:UserComment", "exif:MakerNote", "photoshop:DateCreated", "xmp:CreateDate", "xmp:ModifyDate",
        ]
        for path in identifyingPaths {
            CGImageMetadataRemoveTagWithPath(pruned, nil, path as CFString)
        }
        let candidates: [CGMutableImageMetadata] = [CGImageMetadataCreateMutable(), pruned]

        for metadata in candidates {
            try? FileManager.default.removeItem(at: out)
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, utType as CFString, 1, nil) else { return false }
            let options: [CFString: Any] = [
                kCGImageDestinationMetadata: metadata,
                kCGImageDestinationMergeMetadata: false,
                kCGImageMetadataShouldExcludeGPS: true,
                kCGImageMetadataShouldExcludeXMP: true,
            ]
            // CopyImageSource finalizes the file itself; a CGImageDestinationFinalize call afterwards reports false even on success.
            guard CGImageDestinationCopyImageSource(dest, src, options as CFDictionary, nil),
                  isStrippedCopy(out, source: src, sourceProps: srcProps)
            else { continue }
            return true
        }
        try? FileManager.default.removeItem(at: out)
        return false
    }

    /// True when `url` decodes at the source's pixel size and holds none of the identifying fields: GPS, IPTC, Make/Model, serials, lens, comment, capture dates, maker notes, or XMP.
    private func isStrippedCopy(_ url: URL, source: CGImageSource, sourceProps: [CFString: Any]) -> Bool {
        guard let outSrc = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(outSrc) == 1,
              let outProps = CGImageSourceCopyPropertiesAtIndex(outSrc, 0, nil) as? [CFString: Any],
              (outProps[kCGImagePropertyPixelWidth] as? Int) == (sourceProps[kCGImagePropertyPixelWidth] as? Int),
              (outProps[kCGImagePropertyPixelHeight] as? Int) == (sourceProps[kCGImagePropertyPixelHeight] as? Int),
              CGImageSourceCreateImageAtIndex(outSrc, 0, nil) != nil,
              let bytes = try? Data(contentsOf: url)
        else { return false }

        let identifyingExif: [CFString] = [
            kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifLensModel, kCGImagePropertyExifLensMake,
            kCGImagePropertyExifCameraOwnerName, kCGImagePropertyExifUserComment,
            kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized,
        ]
        let outExif = outProps[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let outTIFF = outProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let leaksField = outProps[kCGImagePropertyGPSDictionary] != nil
            || outProps[kCGImagePropertyIPTCDictionary] != nil
            || outTIFF[kCGImagePropertyTIFFMake] != nil
            || outTIFF[kCGImagePropertyTIFFModel] != nil
            || identifyingExif.contains(where: { outExif[$0] != nil })
            || outProps.keys.contains(where: { ($0 as String).hasPrefix("{Maker") })
        guard !leaksField else { return false }

        // Identifying values must not survive as raw bytes (for example a stale XMP packet), even where ImageIO no longer parses them.
        let identifyingNames: Set<String> = [
            "GPSLatitude", "GPSLongitude", "Make", "Model", "BodySerialNumber", "LensModel", "LensMake",
            "CameraOwnerName", "UserComment", "DateTimeOriginal", "DateTimeDigitized", "DateCreated", "CreateDate", "ModifyDate",
        ]
        let sourceTags = (CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap { CGImageMetadataCopyTags($0) } as? [CGImageMetadataTag]) ?? []
        let identifyingText = sourceTags
            .filter { (CGImageMetadataTagCopyName($0) as String?).map(identifyingNames.contains) ?? false }
            .compactMap { CGImageMetadataTagCopyValue($0) as? String }
            .filter { $0.utf8.count >= 8 }
        return identifyingText.allSatisfy { bytes.range(of: Data($0.utf8)) == nil }
    }

    /// Rewrites every GIF frame, keeping only each frame's delay timing and the file's loop count, so comments and XMP are dropped.
    private func stripGIFMetadata(file: URL, out: URL) -> Result<URL, ConversionError> {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil) else {
            return .failure("The source image could not be read.")
        }
        let count = CGImageSourceGetCount(src)
        guard count > 0,
              let dest = CGImageDestinationCreateWithURL(out as CFURL, "com.compuserve.gif" as CFString, count, nil)
        else { return .failure("Could not create the GIF file.") }

        let fileGIF = (CGImageSourceCopyProperties(src, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
        var fileLevel: [CFString: Any] = [:]
        if let loop = fileGIF[kCGImagePropertyGIFLoopCount] { fileLevel[kCGImagePropertyGIFLoopCount] = loop }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: fileLevel] as CFDictionary)

        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(src, index, nil) else {
                try? FileManager.default.removeItem(at: out)
                return .failure("Frame \(index + 1) of \(count) could not be read.")
            }
            let gif = (CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
            var timing: [CFString: Any] = [:]
            for key in [kCGImagePropertyGIFDelayTime, kCGImagePropertyGIFUnclampedDelayTime] {
                if let value = gif[key] { timing[key] = value }
            }
            CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary: timing] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest),
              let outSrc = CGImageSourceCreateWithURL(out as CFURL, nil),
              CGImageSourceGetCount(outSrc) == count
        else {
            try? FileManager.default.removeItem(at: out)
            return .failure("Could not write \(out.lastPathComponent).")
        }
        return .success(out)
    }

    /// Re-encodes decoded pixels, which carry no metadata. Lossy output steps the quality down while it is still larger than the input.
    private func reencodeWithoutMetadata(_ image: CGImage, format: ConversionFormat, inputBytes: Int, out: URL) -> Result<URL, ConversionError> {
        var result = saveCGImage(image, to: out, format: format, quality: 0.95)
        guard [ConversionFormat.jpg, .heic, .webp].contains(format) else { return result }
        for quality in [CGFloat(0.9), 0.85, 0.8] where fileSize(of: out) > inputBytes {
            result = saveCGImage(image, to: out, format: format, quality: quality)
        }
        return result
    }

    private func adjustImage(file: URL, adjustments: ImageAdjustments) -> Result<URL, ConversionError> {
        guard let srcCG = loadCGImage(from: file) else {
            return .failure("Could not read the image.")
        }
        var ciImage = CIImage(cgImage: srcCG)

        if abs(adjustments.exposure) > 0.001, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(adjustments.exposure, forKey: kCIInputEVKey)
            if let out = f.outputImage { ciImage = out }
        }
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(adjustments.brightness, forKey: kCIInputBrightnessKey)
            f.setValue(adjustments.contrast, forKey: kCIInputContrastKey)
            f.setValue(adjustments.saturation, forKey: kCIInputSaturationKey)
            if let out = f.outputImage { ciImage = out }
        }
        if abs(adjustments.temperature - 6500) > 10, let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: CGFloat(adjustments.temperature), y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
            if let out = f.outputImage { ciImage = out }
        }
        if adjustments.sharpness > 0.01, let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(adjustments.sharpness, forKey: kCIInputSharpnessKey)
            if let out = f.outputImage { ciImage = out }
        }
        if adjustments.vignette > 0.01, let f = CIFilter(name: "CIVignette") {
            f.setValue(ciImage, forKey: kCIInputImageKey)
            f.setValue(adjustments.vignette, forKey: kCIInputIntensityKey)
            f.setValue(1.5, forKey: kCIInputRadiusKey)
            if let out = f.outputImage { ciImage = out }
        }
        if adjustments.blur > 0.05, let f = CIFilter(name: "CIGaussianBlur") {
            let extent = ciImage.extent
            f.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
            f.setValue(adjustments.blur, forKey: kCIInputRadiusKey)
            if let out = f.outputImage?.cropped(to: extent) { ciImage = out }
        }

        let context = CIContext(options: nil)
        guard let rendered = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: srcCG.width, height: srcCG.height)) else {
            return .failure("Could not render the photo adjustments.")
        }

        let fmt = ConversionFormat.detect(for: file) ?? .png
        let out = outputURL(for: file, ext: fmt.fileExtension, suffix: "-edited", forceUnique: true)
        return saveCGImage(rendered, to: out, format: fmt, quality: 0.92)
    }

    private func frameImage(file: URL, options: FrameImageOptions) -> Result<URL, ConversionError> {
        guard let srcCG = loadCGImage(from: file) else {
            return .failure("Could not read the image.")
        }

        let pad = CGFloat(options.padding)
        let imgW = CGFloat(srcCG.width)
        let imgH = CGFloat(srcCG.height)

        var canvasW = imgW + pad * 2
        var canvasH = imgH + pad * 2

        switch options.canvasRatio {
        case .automatic:
            break
        case .square:
            let side = max(canvasW, canvasH)
            canvasW = side; canvasH = side
        case .landscape:
            let targetRatio: CGFloat = 16.0 / 9.0
            if canvasW / canvasH < targetRatio {
                canvasW = canvasH * targetRatio
            } else {
                canvasH = canvasW / targetRatio
            }
        case .portrait:
            let targetRatio: CGFloat = 4.0 / 5.0
            if canvasW / canvasH < targetRatio {
                canvasW = canvasH * targetRatio
            } else {
                canvasH = canvasW / targetRatio
            }
        }

        let w = max(64, min(8192, Int(canvasW.rounded())))
        let h = max(64, min(8192, Int(canvasH.rounded())))

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return .failure("Could not prepare the image background.") }

        // Draw gradient background preset
        let (c1, c2) = options.background.colors
        if let grad = CGGradient(
            colorsSpace: space,
            colors: [c1.cgColor, c2.cgColor] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: CGFloat(h)),
                end: CGPoint(x: CGFloat(w), y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        let imgRect = CGRect(
            x: (CGFloat(w) - imgW) * 0.5,
            y: (CGFloat(h) - imgH) * 0.5,
            width: imgW,
            height: imgH
        )
        let cr = CGFloat(options.cornerRadius)
        let roundedPath = CGPath(roundedRect: imgRect, cornerWidth: cr, cornerHeight: cr, transform: nil)

        // Shadow follows the clipped image's alpha (transparency layer), so transparent pixels stay see-through.
        ctx.saveGState()
        if options.shadowRadius > 0 {
            ctx.setShadow(
                offset: CGSize(width: 0, height: -options.shadowRadius * 0.35),
                blur: CGFloat(options.shadowRadius),
                color: NSColor.black.withAlphaComponent(0.42).cgColor
            )
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(roundedPath)
        ctx.clip()
        ctx.draw(srcCG, in: imgRect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        guard let framed = ctx.makeImage() else {
            return .failure("Could not finish adding the background.")
        }

        let out = outputURL(for: file, ext: "png", suffix: "-framed", forceUnique: true)
        return saveCGImage(framed, to: out, format: .png, quality: 0.95)
    }

    private func cropImage(file: URL, options: FileToolOptions) -> Result<URL, ConversionError> {
        guard let srcCG = loadCGImage(from: file) else {
            return .failure("Could not read the image.")
        }
        let w = srcCG.width
        let h = srcCG.height
        // Whole pixels: origin rounds down, size rounds to nearest, so 0.9 of 1000 px is exactly 900 px.
        let x = max(0, min(w - 2, Int((options.cropX * Double(w)).rounded(.down))))
        let y = max(0, min(h - 2, Int(((1.0 - options.cropY - options.cropHeight) * Double(h)).rounded(.down))))
        let cw = max(2, min(w - x, Int((options.cropWidth * Double(w)).rounded())))
        let ch = max(2, min(h - y, Int((options.cropHeight * Double(h)).rounded())))

        guard let cropped = srcCG.cropping(to: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(cw), height: CGFloat(ch))) else {
            return .failure("Could not create the cropped image.")
        }

        let fmt = ConversionFormat.detect(for: file) ?? .png
        let out = outputURL(for: file, ext: fmt.fileExtension, suffix: "-cropped", forceUnique: true)
        return saveCGImage(cropped, to: out, format: fmt, quality: 0.92)
    }

    private func annotateImage(file: URL, annotations: [ImageAnnotation]) -> Result<URL, ConversionError> {
        guard let srcCG = loadCGImage(from: file) else {
            return .failure("Could not read the image.")
        }
        let w = srcCG.width
        let h = srcCG.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return .failure("Could not prepare the annotated image.") }

        let canvas = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(srcCG, in: canvas)

        let scale = max(1.0, CGFloat(max(w, h)) / 1000.0)

        for ann in annotations {
            let p1 = CGPoint(x: ann.startX * Double(w), y: ann.startY * Double(h))
            let p2 = CGPoint(x: ann.endX * Double(w), y: ann.endY * Double(h))
            let box = CGRect(
                x: min(p1.x, p2.x),
                y: min(p1.y, p2.y),
                width: max(24, abs(p2.x - p1.x)),
                height: max(24, abs(p2.y - p1.y))
            )

            ctx.saveGState()
            let strokeW = CGFloat(ann.lineWidth) * scale
            ctx.setStrokeColor(ann.color.cgColor)
            ctx.setFillColor(ann.color.cgColor)
            ctx.setLineWidth(strokeW)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            switch ann.kind {
            case .arrow:
                ctx.move(to: p1)
                ctx.addLine(to: p2)
                ctx.strokePath()
                // Arrowhead at p2
                let angle = atan2(p2.y - p1.y, p2.x - p1.x)
                let headLen: CGFloat = 18 * scale
                let a1 = CGPoint(x: p2.x - headLen * cos(angle - .pi / 6), y: p2.y - headLen * sin(angle - .pi / 6))
                let a2 = CGPoint(x: p2.x - headLen * cos(angle + .pi / 6), y: p2.y - headLen * sin(angle + .pi / 6))
                ctx.move(to: p2)
                ctx.addLine(to: a1)
                ctx.move(to: p2)
                ctx.addLine(to: a2)
                ctx.strokePath()

            case .rectangle:
                ctx.stroke(box)

            case .ellipse:
                ctx.strokeEllipse(in: box)

            case .highlighter:
                ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.38).cgColor)
                ctx.fill(box)

            case .number:
                let r: CGFloat = 16 * scale
                let badgeRect = CGRect(x: p1.x - r, y: p1.y - r, width: r * 2, height: r * 2)
                ctx.fillEllipse(in: badgeRect)
                drawCGText("\(ann.number)", in: badgeRect, fontSize: 15 * scale, color: .white, in: ctx)

            case .text:
                let bgRect = CGRect(x: p1.x, y: p1.y, width: max(120 * scale, CGFloat(ann.text.count) * 11 * scale), height: 32 * scale)
                ctx.setFillColor(ann.color.withAlphaComponent(0.90).cgColor)
                let path = CGPath(roundedRect: bgRect, cornerWidth: 6 * scale, cornerHeight: 6 * scale, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()
                drawCGText(ann.text, in: bgRect, fontSize: 14 * scale, color: .white, in: ctx)

            case .magnifier:
                let r: CGFloat = 48 * scale
                let loupeRect = CGRect(x: p1.x - r, y: p1.y - r, width: r * 2, height: r * 2)
                let zoom = CGFloat(ann.magnification)
                let zoomedRect = CGRect(
                    x: p1.x - (p1.x * zoom),
                    y: p1.y - (p1.y * zoom),
                    width: CGFloat(w) * zoom,
                    height: CGFloat(h) * zoom
                )
                // Copy blend: the zoomed source replaces the loupe's pixels. Source-over would stack it on the unzoomed copy, so translucent sources come out darker and more opaque inside the loupe.
                ctx.saveGState()
                ctx.setAlpha(1)
                ctx.setBlendMode(.copy)
                ctx.addEllipse(in: loupeRect)
                ctx.clip()
                ctx.draw(srcCG, in: zoomedRect)
                ctx.restoreGState()
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(3 * scale)
                ctx.strokeEllipse(in: loupeRect)
            }
            ctx.restoreGState()
        }

        guard let outCG = ctx.makeImage() else {
            return .failure("Could not prepare the annotated image.")
        }
        let fmt = ConversionFormat.detect(for: file) ?? .png
        let out = outputURL(for: file, ext: fmt.fileExtension, suffix: "-annotated", forceUnique: true)
        return saveCGImage(outCG, to: out, format: fmt, quality: 0.92)
    }

    private func drawCGText(_ text: String, in rect: CGRect, fontSize: CGFloat, color: NSColor, in ctx: CGContext) {
        let attr = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: color,
            ]
        )
        let line = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(
            x: rect.midX - bounds.width * 0.5,
            y: rect.midY - bounds.height * 0.32
        )
        CTLineDraw(line, ctx)
    }

    private func createCollage(from files: [URL], options: CollageOptions) -> Result<URL, ConversionError> {
        let images = files.compactMap { loadCGImage(from: $0) }
        guard images.count >= 2 else {
            return .failure("Could not read at least two images for the collage.")
        }

        let pad = CGFloat(options.padding)
        let gap = CGFloat(options.spacing)
        let totalW = CGFloat(max(640, min(4096, options.width)))
        let layout = collageLayout(images, style: options.style, columns: options.columns, pad: pad, gap: gap, totalW: totalW)
        let totalH = layout.height

        let w = Int(totalW.rounded())
        let h = Int(totalH.rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return .failure("Could not create the collage canvas.") }

        switch options.background {
        case .white:
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        case .black:
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        case .transparent:
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        }

        let cr = CGFloat(options.cornerRadius)
        for (img, frame) in zip(images, layout.frames) {
            // Layout is top-down; CoreGraphics measures the origin from the bottom.
            let rect = CGRect(x: frame.minX, y: totalH - frame.maxY, width: frame.width, height: frame.height)

            ctx.saveGState()
            let clipPath = CGPath(roundedRect: rect, cornerWidth: cr, cornerHeight: cr, transform: nil)
            ctx.addPath(clipPath)
            ctx.clip()

            // Aspect-fill cell
            let imgAspect = CGFloat(img.width) / CGFloat(max(1, img.height))
            let cellAspect = rect.width / rect.height
            var drawRect = rect
            if imgAspect > cellAspect {
                let dw = rect.height * imgAspect
                drawRect.origin.x -= (dw - rect.width) * 0.5
                drawRect.size.width = dw
            } else {
                let dh = rect.width / imgAspect
                drawRect.origin.y -= (dh - rect.height) * 0.5
                drawRect.size.height = dh
            }
            ctx.draw(img, in: drawRect)
            ctx.restoreGState()
        }

        guard let collageCG = ctx.makeImage() else {
            return .failure("Could not render the collage.")
        }
        let out = outputURL(for: files[0], ext: "png", suffix: "-collage", forceUnique: true)
        return saveCGImage(collageCG, to: out, format: .png, quality: 0.94)
    }

    private func redactImage(
        file: URL,
        rectangles: [RedactionRectangle],
        style: RedactionStyle
    ) -> Result<URL, ConversionError> {
        guard !rectangles.isEmpty else {
            return .failure("Draw at least one area to redact.")
        }
        guard let srcCG = loadCGImage(from: file) else {
            return .failure("Could not read the image.")
        }
        let w = CGFloat(srcCG.width)
        let h = CGFloat(srcCG.height)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: Int(w), height: Int(h),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return .failure("Could not prepare the redacted photo.") }

        ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: w, height: h))

        var blurredCG: CGImage?
        if style == .blur {
            let ci = CIImage(cgImage: srcCG)
            if let f = CIFilter(name: "CIGaussianBlur") {
                f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
                f.setValue(max(18.0, Double(max(w, h)) * 0.025), forKey: kCIInputRadiusKey)
                if let outCI = f.outputImage?.cropped(to: ci.extent) {
                    blurredCG = CIContext(options: nil).createCGImage(outCI, from: ci.extent)
                }
            }
        }

        for r in rectangles {
            let box = CGRect(x: CGFloat(r.x) * w, y: CGFloat(r.y) * h, width: CGFloat(r.width) * w, height: CGFloat(r.height) * h)
            ctx.saveGState()
            if style == .blur, let blurredCG {
                ctx.clip(to: box)
                ctx.draw(blurredCG, in: CGRect(x: 0, y: 0, width: w, height: h))
            } else {
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(box)
            }
            ctx.restoreGState()
        }

        guard let outCG = ctx.makeImage() else {
            return .failure("Could not prepare the redacted photo.")
        }
        let fmt = ConversionFormat.detect(for: file) ?? .png
        let out = outputURL(for: file, ext: fmt.fileExtension, suffix: "-redacted", forceUnique: true)
        return saveCGImage(outCG, to: out, format: fmt, quality: 0.92)
    }

    // MARK: - Audio & Video File Tools

    private func normalizeAudio(file: URL, options: FileToolOptions) -> Result<URL, ConversionError> {
        let ff = ToolLocator.ffmpeg(settings)
        guard !ff.isEmpty else { return .failure("ffmpeg is required for audio normalization.") }
        guard let info = MediaProbe.probe(file) else { return .failure("Could not read this media file.") }
        guard info.hasAudio else { return .failure("This file has no audio track.") }
        let ext = file.pathExtension.isEmpty ? "mp3" : file.pathExtension
        guard let codecArgs = MediaProbe.audioEncoderArgs(forExtension: ext, source: info) else {
            return .failure("Ogg output needs the libvorbis or libopus encoder, and this ffmpeg build has neither.")
        }
        let out = outputURL(for: file, ext: ext, suffix: "-normalized", forceUnique: true)
        // loudnorm upsamples internally; resampling back to the source rate keeps the output rate unchanged.
        let filter = String(
            format: "loudnorm=I=%.1f:LRA=%.1f:TP=%.1f",
            options.normalizationTargetLoudness,
            options.normalizationLoudnessRange,
            options.normalizationTruePeak
        ) + ",aresample=\(info.audioSampleRate ?? 48000)"
        let res = ToolRunner.run(
            ff,
            arguments: ["-y", "-i", file.path, "-af", filter, "-c:v", "copy"] + codecArgs + [out.path],
            timeout: Double(settings.timeoutSeconds)
        )
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Audio normalization failed." : lastErrorLine(res.stderr)))
        }
        return .success(out)
    }

    private func trimMedia(file: URL, options: FileToolOptions, isAudioOnly: Bool) -> Result<URL, ConversionError> {
        let ff = ToolLocator.ffmpeg(settings)
        guard !ff.isEmpty else { return .failure("ffmpeg is required for trimming.") }
        guard let info = MediaProbe.probe(file) else { return .failure("Could not read this media file.") }
        let start = max(0, options.trimStartSeconds)
        if info.duration > 0, start >= info.duration {
            return .failure("Start time is past the end of the file.")
        }
        let ext = file.pathExtension.isEmpty ? (isAudioOnly ? "mp3" : "mp4") : file.pathExtension
        let out = outputURL(for: file, ext: ext, suffix: "-trimmed", forceUnique: true)

        var args = [
            "-y",
            "-ss", String(format: "%.2f", start),
            "-i", file.path,
            "-t", String(format: "%.2f", max(0.2, options.trimDurationSeconds)),
        ]
        if isAudioOnly && options.autoTrimSilence {
            let thresh = Int(options.silenceThresholdDB)
            args.append(contentsOf: ["-af", "silenceremove=start_periods=1:start_threshold=\(thresh)dB:stop_periods=1:stop_threshold=\(thresh)dB"])
        }
        if info.hasAudio {
            guard let codecArgs = MediaProbe.audioEncoderArgs(forExtension: ext, source: info) else {
                return .failure("Ogg output needs the libvorbis or libopus encoder, and this ffmpeg build has neither.")
            }
            args.append(contentsOf: codecArgs)
        }
        args.append(out.path)

        let res = ToolRunner.run(ff, arguments: args, timeout: Double(settings.timeoutSeconds))
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Trimming failed." : lastErrorLine(res.stderr)))
        }
        if let produced = MediaProbe.probe(out), produced.duration <= 0.05 {
            try? FileManager.default.removeItem(at: out)
            return .failure("Trimming produced an empty file.")
        }
        return .success(out)
    }

    private func convertAudioChannels(file: URL, options: FileToolOptions) -> Result<URL, ConversionError> {
        let ff = ToolLocator.ffmpeg(settings)
        guard !ff.isEmpty else { return .failure("ffmpeg is required for channel conversion.") }
        guard let info = MediaProbe.probe(file) else { return .failure("Could not read this media file.") }
        guard info.hasAudio else { return .failure("This file has no audio track.") }
        let ext = file.pathExtension.isEmpty ? "wav" : file.pathExtension
        guard let codecArgs = MediaProbe.audioEncoderArgs(forExtension: ext, source: info) else {
            return .failure("Ogg output needs the libvorbis or libopus encoder, and this ffmpeg build has neither.")
        }
        let out = outputURL(for: file, ext: ext, suffix: "-channels", forceUnique: true)
        let left = Double(options.audioLeftVolume)
        let right = Double(options.audioRightVolume)
        let fromMono = info.audioChannels == 1
        let coefficient = { (value: Double) in String(format: "%.3f", value) }
        let panFilter: String
        if options.audioChannelCount == 1 {
            // Downmix averages both channels; the 0.5 factor is folded into each coefficient.
            panFilter = fromMono
                ? "pan=mono|c0=\(coefficient(left))*c0"
                : "pan=mono|c0=\(coefficient(0.5 * left))*c0+\(coefficient(0.5 * right))*c1"
        } else {
            panFilter = fromMono
                ? "pan=stereo|c0=\(coefficient(left))*c0|c1=\(coefficient(right))*c0"
                : "pan=stereo|c0=\(coefficient(left))*c0|c1=\(coefficient(right))*c1"
        }
        let res = ToolRunner.run(
            ff,
            arguments: ["-y", "-i", file.path, "-af", panFilter, "-c:v", "copy"] + codecArgs + [out.path],
            timeout: Double(settings.timeoutSeconds)
        )
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Channel conversion failed." : lastErrorLine(res.stderr)))
        }
        return .success(out)
    }

    private func createAudioVisualizer(file: URL, options: FileToolOptions) -> Result<URL, ConversionError> {
        let ff = ToolLocator.ffmpeg(settings)
        guard !ff.isEmpty else { return .failure("ffmpeg is required for audio visualization.") }
        guard let info = MediaProbe.probe(file) else { return .failure("Could not read this media file.") }
        guard info.hasAudio else { return .failure("This file has no audio track.") }
        let out = outputURL(for: file, ext: "mp4", suffix: "-visualizer", forceUnique: true)
        // Matches Tangerine's showwaves filter at 0x1001136: mode=cline:rate=30:colors=0xff5200:scale=sqrt,format=yuv420p
        let filter = "[0:a]showwaves=s=1280x720:mode=cline:rate=30:colors=0xff5200:scale=sqrt,format=yuv420p[v]"
        let res = ToolRunner.run(
            ff,
            arguments: [
                "-y", "-i", file.path,
                "-filter_complex", filter,
                "-map", "[v]", "-map", "0:a",
                "-c:v", "libx264", "-preset", "fast", "-crf", "22",
                "-c:a", "aac", "-b:a", "192k", "-shortest",
                out.path
            ],
            timeout: Double(settings.timeoutSeconds)
        )
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Could not create audio visualization." : lastErrorLine(res.stderr)))
        }
        return .success(out)
    }

    private func muteVideo(file: URL) -> Result<URL, ConversionError> {
        let ff = ToolLocator.ffmpeg(settings)
        guard !ff.isEmpty else { return .failure("ffmpeg is required to mute video.") }
        let ext = file.pathExtension.isEmpty ? "mp4" : file.pathExtension
        let out = outputURL(for: file, ext: ext, suffix: "-muted", forceUnique: true)
        let res = ToolRunner.run(
            ff,
            arguments: ["-y", "-i", file.path, "-an", "-c:v", "copy", out.path],
            timeout: Double(settings.timeoutSeconds)
        )
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Muting video failed." : lastErrorLine(res.stderr)))
        }
        return .success(out)
    }

    private func cropVideo(file: URL, options: FileToolOptions) -> Result<URL, ConversionError> {
        let ff = ToolLocator.ffmpeg(settings)
        guard !ff.isEmpty else { return .failure("ffmpeg is required to crop video.") }
        let ext = file.pathExtension.isEmpty ? "mp4" : file.pathExtension
        let out = outputURL(for: file, ext: ext, suffix: "-cropped", forceUnique: true)
        let filter = String(
            format: "crop=iw*%.3f:ih*%.3f:iw*%.3f:ih*%.3f",
            options.cropWidth, options.cropHeight, options.cropX, options.cropY
        )
        // WebM and Matroska cannot carry AAC, so their audio is re-encoded to Opus.
        let audioArgs = ["mkv", "webm"].contains(ext.lowercased()) ? ["-c:a", "libopus"] : ["-c:a", "copy"]
        let res = ToolRunner.run(
            ff,
            arguments: ["-y", "-i", file.path, "-vf", filter] + audioArgs + [out.path],
            timeout: Double(settings.timeoutSeconds)
        )
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Video crop failed." : lastErrorLine(res.stderr)))
        }
        return .success(out)
    }

    private func changeVideoSpeed(file: URL, speed: Double) -> Result<URL, ConversionError> {
        let ff = ToolLocator.ffmpeg(settings)
        guard !ff.isEmpty else { return .failure("ffmpeg is required to change video speed.") }
        guard let info = MediaProbe.probe(file) else { return .failure("Could not read this media file.") }
        let clamped = max(0.25, min(4.0, speed))
        let ext = file.pathExtension.isEmpty ? "mp4" : file.pathExtension
        let out = outputURL(for: file, ext: ext, suffix: "-\(String(format: "%.2gx", clamped))", forceUnique: true)
        var args = ["-y", "-i", file.path]
        if info.hasVideo {
            // Retiming frames with setpts, then resampling to the source rate keeps the frame cadence constant.
            let fps = info.frameRate ?? 30
            args += ["-vf", String(format: "setpts=PTS/%.4f,fps=%.3f", clamped, fps)]
        }
        if info.hasAudio {
            // atempo accepts 0.5...2.0 per stage, so slower or faster speeds chain several stages.
            var stages: [String] = []
            var remaining = clamped
            while remaining < 0.5 {
                stages.append("atempo=0.5")
                remaining /= 0.5
            }
            while remaining > 2.0 {
                stages.append("atempo=2.0")
                remaining /= 2.0
            }
            stages.append(String(format: "atempo=%.4f", remaining))
            args += ["-af", stages.joined(separator: ",")]
            guard let codecArgs = MediaProbe.audioEncoderArgs(forExtension: ext, source: info) else {
                return .failure("Ogg output needs the libvorbis or libopus encoder, and this ffmpeg build has neither.")
            }
            args += codecArgs
        } else {
            args.append("-an")
        }
        args.append(out.path)
        let res = ToolRunner.run(ff, arguments: args, timeout: Double(settings.timeoutSeconds))
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Changing video speed failed." : lastErrorLine(res.stderr)))
        }
        return .success(out)
    }

    private func joinVideos(_ files: [URL]) -> Result<URL, ConversionError> {
        let ff = ToolLocator.ffmpeg(settings)
        guard !ff.isEmpty else { return .failure("ffmpeg is required to join videos.") }
        var infos: [MediaInfo] = []
        for file in files {
            guard let info = MediaProbe.probe(file) else { return .failure("Could not read \(file.lastPathComponent).") }
            guard info.hasVideo else { return .failure("\(file.lastPathComponent) has no video track.") }
            guard info.duration > 0 else { return .failure("Could not read the length of \(file.lastPathComponent).") }
            infos.append(info)
        }
        guard let firstWidth = infos[0].width, let firstHeight = infos[0].height else {
            return .failure("Could not read the size of \(files[0].lastPathComponent).")
        }
        // Every clip is scaled and padded to the first clip's size (even dimensions for yuv420p).
        let width = max(2, firstWidth / 2 * 2)
        let height = max(2, firstHeight / 2 * 2)

        var inputs: [String] = []
        var segments: [String] = []
        var graph: [String] = []
        for (index, info) in infos.enumerated() {
            inputs += ["-i", files[index].path]
            graph.append("[\(index):v]scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v\(index)]")
            if info.hasAudio {
                graph.append("[\(index):a]aresample=48000,aformat=channel_layouts=stereo[a\(index)]")
            } else {
                graph.append(String(format: "anullsrc=channel_layout=stereo:sample_rate=48000,atrim=duration=%.3f[a%d]", info.duration, index))
            }
            segments.append("[v\(index)][a\(index)]")
        }
        graph.append(segments.joined() + "concat=n=\(files.count):v=1:a=1[outv][outa]")

        let out = outputURL(for: files[0], ext: "mp4", suffix: "-joined", forceUnique: true)
        let res = ToolRunner.run(
            ff,
            arguments: ["-y"] + inputs + [
                "-filter_complex", graph.joined(separator: ";"),
                "-map", "[outv]", "-map", "[outa]",
                "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p",
                "-c:a", "aac", out.path
            ],
            timeout: Double(settings.timeoutSeconds)
        )
        guard res.succeeded else {
            return .failure(ConversionError(res.stderr.isEmpty ? "Joining videos failed." : lastErrorLine(res.stderr)))
        }
        return .success(out)
    }

    private func extractVideoSnapshots(file: URL) -> Result<[URL], ConversionError> {
        let info = MediaProbe.probe(file)
        if let info, !info.hasVideo {
            return .failure("This file has no video track.")
        }
        let asset = AVURLAsset(url: file)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Exact frame times: the default tolerance can snap to a neighbouring keyframe.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var durationSec: Double = 4.0
        if let duration = info?.duration, duration > 0 {
            durationSec = duration
        } else {
            let sem = DispatchSemaphore(value: 0)
            Task {
                if let d = try? await asset.load(.duration) {
                    let s = CMTimeGetSeconds(d)
                    if s.isFinite && s > 0 { durationSec = s }
                }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 5)
        }

        let sampleFractions: [Double] = [0.1, 0.35, 0.65, 0.9]
        var saved: [URL] = []

        for (idx, frac) in sampleFractions.enumerated() {
            let seconds = durationSec * frac
            let out = outputURL(for: file, ext: "png", suffix: String(format: "-frame-%02d", idx + 1), forceUnique: true)
            let t = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cg = try? generator.copyCGImage(at: t, actualTime: nil),
               case .success(let url) = saveCGImage(cg, to: out, format: .png, quality: 0.95) {
                saved.append(url)
            } else {
                // AVFoundation cannot decode some containers (WebM, MKV, AVI); ffmpeg can.
                let ff = ToolLocator.ffmpeg(settings)
                let res: ToolResult? = ff.isEmpty ? nil : ToolRunner.run(
                    ff,
                    arguments: ["-y", "-ss", String(format: "%.3f", seconds), "-i", file.path, "-frames:v", "1", out.path],
                    timeout: Double(settings.timeoutSeconds)
                )
                if res?.succeeded == true, FileManager.default.fileExists(atPath: out.path) {
                    saved.append(out)
                }
            }
        }

        if !saved.isEmpty {
            return .success(saved)
        }
        return .failure("Could not extract any frames from this video.")
    }

    // MARK: - PDF Tools

    private func splitPDF(file: URL) -> Result<[URL], ConversionError> {
        guard let doc = PDFDocument(url: file), doc.pageCount > 0 else {
            return .failure("This PDF has no pages.")
        }
        var outputs: [URL] = []
        for idx in 0..<doc.pageCount {
            guard let page = doc.page(at: idx) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let out = outputURL(for: file, ext: "pdf", suffix: String(format: "-page-%02d", idx + 1), forceUnique: true)
            if single.write(to: out) {
                outputs.append(out)
            }
        }
        guard !outputs.isEmpty else { return .failure("Could not write PDF pages.") }
        return .success(outputs)
    }

    private func organizePDF(file: URL, options: FileToolOptions) -> Result<URL, ConversionError> {
        guard let doc = PDFDocument(url: file), doc.pageCount > 0 else {
            return .failure("This PDF has no pages.")
        }
        let order = options.pdfPageOrder.isEmpty ? Array(0..<doc.pageCount) : options.pdfPageOrder
        let organized = PDFDocument()
        for pageIdx in order {
            guard pageIdx >= 0, pageIdx < doc.pageCount,
                  let page = doc.page(at: pageIdx)?.copy() as? PDFPage
            else { continue }
            if let extraRot = options.pdfPageRotations[pageIdx] {
                page.rotation = (page.rotation + extraRot) % 360
            }
            organized.insert(page, at: organized.pageCount)
        }
        let out = outputURL(for: file, ext: "pdf", suffix: "-organized", forceUnique: true)
        guard organized.write(to: out) else {
            return .failure("PDFKit could not write the organized PDF.")
        }
        return .success(out)
    }

    private func mergePDFs(_ files: [URL]) -> Result<URL, ConversionError> {
        let merged = PDFDocument()
        for file in files {
            guard let doc = PDFDocument(url: file) else {
                return .failure("Could not read PDF \(file.lastPathComponent).")
            }
            for idx in 0..<doc.pageCount {
                if let page = doc.page(at: idx) {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        guard merged.pageCount > 0 else { return .failure("No PDF pages found to merge.") }
        let out = outputURL(for: files[0], ext: "pdf", suffix: "-merged", forceUnique: true)
        guard merged.write(to: out) else { return .failure("PDFKit could not write the combined PDF.") }
        return .success(out)
    }

    private func convertToAVIF(file: URL, options: ConversionOptions) -> Result<URL, ConversionError> {
        guard let cgImage = loadCGImage(from: file) else {
            return .failure("The source image could not be read.")
        }
        let out = outputURL(for: file, ext: "avif")
        if imageUTType(for: .avif) != nil {
            return saveCGImage(cgImage, to: out, format: .avif, quality: options.quality.imageCompressionQuality)
        }
        // Fallback: ffmpeg's SVT-AV1 encoder, when this build includes it.
        let ff = ToolLocator.ffmpeg(settings)
        let timeout = Double(settings.timeoutSeconds)
        guard !ff.isEmpty,
              ToolRunner.run(ff, arguments: ["-hide_banner", "-encoders"], timeout: timeout).stdout.contains("libsvtav1")
        else {
            return .failure("AVIF encoding is not available on this Mac.")
        }
        let crf: String
        switch options.quality {
        case .compact: crf = "45"
        case .balanced: crf = "35"
        case .high: crf = "25"
        }
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("daisy-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: png) }
        if case .failure(let error) = writeImage(cgImage, to: png, utType: "public.png") {
            return .failure(error)
        }
        let res = ToolRunner.run(
            ff,
            arguments: ["-y", "-i", png.path, "-frames:v", "1", "-c:v", "libsvtav1", "-crf", crf, "-pix_fmt", "yuv420p", out.path],
            timeout: timeout
        )
        guard res.succeeded else {
            let detail = lastErrorLine(res.stderr)
            return .failure(ConversionError(detail.isEmpty ? "AVIF encoding failed." : detail))
        }
        return .success(out)
    }

    /// Top-down frames, index-aligned with `images`, plus the canvas height they require.
    private func collageLayout(
        _ images: [CGImage],
        style: CollageStyle,
        columns: Int,
        pad: CGFloat,
        gap: CGFloat,
        totalW: CGFloat
    ) -> (frames: [CGRect], height: CGFloat) {
        let innerW = totalW - pad * 2
        let cols: Int
        switch style {
        case .horizontal: cols = images.count
        case .vertical: cols = 1
        case .grid: cols = max(1, min(columns, images.count))
        case .featured: cols = max(1, min(columns, images.count - 1))
        }
        let cellW = (innerW - gap * CGFloat(cols - 1)) / CGFloat(cols)
        var frames: [CGRect] = []
        var y = pad
        var index = 0
        if style == .featured {
            // The first image is a full-width hero; the rest follow in a grid below it.
            let heroH = cellW * CGFloat(cols) * 0.56
            frames.append(CGRect(x: pad, y: y, width: innerW, height: heroH))
            y += heroH + gap
            index = 1
        }
        while index < images.count {
            let rowEnd = min(images.count, index + cols)
            let rowH: CGFloat
            if style == .vertical {
                // Each vertical cell takes its image's own aspect, clamped so panoramas stay sane.
                let aspect = CGFloat(images[index].width) / CGFloat(max(1, images[index].height))
                rowH = cellW / min(2.5, max(0.5, aspect))
            } else {
                rowH = cellW * 0.75
            }
            for i in index..<rowEnd {
                let col = CGFloat(i - index)
                frames.append(CGRect(x: pad + col * (cellW + gap), y: y, width: cellW, height: rowH))
            }
            y += rowH + gap
            index = rowEnd
        }
        return (frames, y - gap + pad)
    }

    /// Writes the highest-quality encoding that fits `targetBytes`, downscaling by 0.8 up to four times if needed.
    private func compressToTarget(_ image: CGImage, format: ConversionFormat, targetBytes: Int, out: URL) -> Result<URL, ConversionError> {
        let lossy = [ConversionFormat.jpg, .heic, .webp].contains(format)
        var current = image
        var smallest = Int.max
        for attempt in 0...4 {
            if attempt > 0 {
                let longest = max(current.width, current.height)
                guard longest > 1,
                      let smaller = resizeCGImage(current, maxDimension: Int(Double(longest) * 0.8))
                else { break }
                current = smaller
            }
            // The lowest quality decides whether this size can fit at all.
            guard let lowest = encodedImageData(current, format: format, quality: lossy ? 0.05 : 0.9) else { break }
            smallest = min(smallest, lowest.count)
            guard lowest.count <= targetBytes else { continue }
            var best = lowest
            if lossy {
                var low: CGFloat = 0.05
                var high: CGFloat = 0.95
                for _ in 0..<8 {
                    let mid = (low + high) / 2
                    guard let data = encodedImageData(current, format: format, quality: mid) else { break }
                    smallest = min(smallest, data.count)
                    if data.count <= targetBytes {
                        best = data
                        low = mid
                    } else {
                        high = mid
                    }
                }
            }
            guard (try? best.write(to: out)) != nil else {
                return .failure("Could not write the compressed image.")
            }
            return .success(out)
        }
        guard smallest < Int.max else {
            return .failure("Could not encode the image.")
        }
        return .failure("Could not reach the target size. Smallest attempt was \(smallest / 1000) KB.")
    }

    private func encodedImageData(_ image: CGImage, format: ConversionFormat, quality: CGFloat) -> Data? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("daisy-\(UUID().uuidString).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard case .success(let written) = saveCGImage(image, to: tmp, format: format, quality: quality) else { return nil }
        return try? Data(contentsOf: written)
    }

    private func fileSize(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int) ?? 0
    }

    /// The ImageIO type identifier for `format`, or nil when this macOS cannot encode it.
    private func imageUTType(for format: ConversionFormat) -> String? {
        switch format {
        case .jpg: return "public.jpeg"
        case .png: return "public.png"
        case .heic: return "public.heic"
        case .tiff: return "public.tiff"
        case .bmp: return "com.microsoft.bmp"
        case .gif: return "com.compuserve.gif"
        case .avif:
            let types = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
            return types.contains("public.avif") ? "public.avif" : nil
        default: return nil
        }
    }

    private func writeImage(
        _ cgImage: CGImage,
        to out: URL,
        utType: String,
        properties: [CFString: Any] = [:]
    ) -> Result<URL, ConversionError> {
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, utType as CFString, 1, nil) else {
            return .failure("Could not create the \(out.pathExtension.uppercased()) file.")
        }
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            return .failure("Could not write \(out.lastPathComponent).")
        }
        return .success(out)
    }

    /// Encodes through `cwebp`, which reads PNG input, so the image is staged as a temporary PNG.
    private func saveWebP(_ cgImage: CGImage, to out: URL, quality: CGFloat) -> Result<URL, ConversionError> {
        let cwebp = ToolLocator.cwebp(settings)
        guard !cwebp.isEmpty else {
            return .failure("cwebp is required for WebP. Run: brew install webp")
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("daisy-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        if case .failure(let error) = writeImage(cgImage, to: tmp, utType: "public.png") {
            return .failure(error)
        }
        let percent = min(100, max(1, Int((quality * 100).rounded())))
        let res = ToolRunner.run(
            cwebp,
            arguments: ["-quiet", "-q", String(percent), tmp.path, "-o", out.path],
            timeout: Double(settings.timeoutSeconds)
        )
        guard res.succeeded else {
            let detail = lastErrorLine(res.stderr)
            return .failure(ConversionError(detail.isEmpty ? "WebP encoding failed." : detail))
        }
        return .success(out)
    }

    /// Draws an NSImage at its point size (one pixel per point), so vector sources such as SVG are not scaled by the screen.
    private func rasterizeNSImage(_ image: NSImage) -> CGImage? {
        let w = Int(image.size.width.rounded())
        let h = Int(image.size.height.rounded())
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    // MARK: - Helpers

    private func loadCGImage(from url: URL) -> CGImage? {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            // Plain image creation ignores EXIF orientation; the thumbnail path applies it.
            // Asking for the source's own longest edge applies the transform without resizing.
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let longest = max(width, height)
            if longest > 0 {
                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: longest,
                ]
                if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) {
                    return cg
                }
            }
            if let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return cg
            }
        }
        if let nsImg = NSImage(contentsOf: url), let cg = rasterizeNSImage(nsImg) {
            return cg
        }
        // Fallback for WebP on older macOS via dwebp if needed
        if url.pathExtension.lowercased() == "webp" {
            let dwebp = ToolLocator.dwebp(settings)
            if !dwebp.isEmpty {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("daisy-\(UUID().uuidString).png")
                defer { try? FileManager.default.removeItem(at: tmp) }
                if ToolRunner.run(dwebp, arguments: [url.path, "-o", tmp.path]).succeeded,
                   let nsImg = NSImage(contentsOf: tmp) {
                    return nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
            }
        }
        return nil
    }

    private func resizeCGImage(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let scale = CGFloat(maxDimension) / max(w, h)
        let nw = max(1, Int((w * scale).rounded()))
        let nh = max(1, Int((h * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: nw, height: nh,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    private func flattenAlphaOntoWhite(_ cgImage: CGImage) -> CGImage? {
        let width = cgImage.width, height = cgImage.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// True when any pixel's alpha is below 255. Scans the full-resolution RGBA8 render. If the render fails, reports true so the PNG path is kept.
    private func hasTransparentPixels(_ cgImage: CGImage) -> Bool {
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return true }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return true }
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] != 255 {
            return true
        }
        return false
    }

    private func saveCGImage(
        _ cgImage: CGImage,
        to out: URL,
        format: ConversionFormat,
        quality: CGFloat
    ) -> Result<URL, ConversionError> {
        // The CGImage is already decoded and upright, and no properties are passed, so no source metadata is written.
        switch format {
        case .webp:
            return saveWebP(cgImage, to: out, quality: quality)
        case .jpg, .heic, .tiff, .bmp, .png, .gif, .avif:
            guard let utType = imageUTType(for: format) else {
                return .failure("\(format.title) encoding is not available on this Mac.")
            }
            var imageToSave = cgImage
            if [ConversionFormat.jpg, .bmp, .gif].contains(format), cgImage.hasAlpha,
               let flat = flattenAlphaOntoWhite(cgImage) {
                imageToSave = flat
            }
            var props: [CFString: Any] = [:]
            if [ConversionFormat.jpg, .heic, .avif].contains(format) {
                props[kCGImageDestinationLossyCompressionQuality] = quality
            }
            return writeImage(imageToSave, to: out, utType: utType, properties: props)
        default:
            // Non-raster targets (SVG, PDF, ...) receive the rendered pixels as PNG under a matching name.
            return writeImage(cgImage, to: out.deletingPathExtension().appendingPathExtension("png"), utType: "public.png")
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func lastErrorLine(_ stderr: String) -> String {
        let lines = stderr.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(2).joined(separator: " ")
    }

    func outputURL(for file: URL, ext: String, suffix: String = "", forceUnique: Bool = false) -> URL {
        let baseDir: URL
        if !settings.outputDirectory.isEmpty {
            baseDir = URL(fileURLWithPath: settings.outputDirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } else {
            baseDir = file.deletingLastPathComponent()
        }
        let stem = outputStem(of: file) + suffix
        func fileName(_ index: Int?) -> String {
            let base = index.map { "\(stem)-\($0)" } ?? stem
            return ext.isEmpty ? base : "\(base).\(ext)"
        }
        var candidate = baseDir.appendingPathComponent(fileName(nil))
        if forceUnique || FileManager.default.fileExists(atPath: candidate.path) {
            var index = 1
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = baseDir.appendingPathComponent(fileName(index))
                index += 1
            }
        }
        return candidate
    }

    private func outputStem(of file: URL) -> String {
        let name = file.lastPathComponent
        for compound in [".tar.gz", ".tgz", ".tar"] where name.lowercased().hasSuffix(compound) {
            return String(name.dropLast(compound.count))
        }
        return file.deletingPathExtension().lastPathComponent
    }
}

extension CGImage {
    var hasAlpha: Bool {
        alphaInfo != .none && alphaInfo != .noneSkipLast && alphaInfo != .noneSkipFirst
    }
}
