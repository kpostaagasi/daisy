// Daisy — QRCodeResultsWindowController and FileToolOptionsWindowController inspired by Tangerine.
import AppKit
import ImageIO
import PDFKit
import SwiftUI
import Vision

// MARK: - QR Code Scanner & Results Window (matching Tangerine's QRCodeResultsWindowController at 0x1002ba9d4)

struct QRCodeResult: Identifiable, Equatable {
    let id = UUID()
    let sourceName: String
    let page: Int?
    let symbology: String
    let text: String
}

final class QRCodeResultsModel: ObservableObject {
    @Published var results: [QRCodeResult] = []
    @Published var errors: [String] = []
    @Published var isLoading = true
    @Published var copiedID: UUID?
    @Published var copiedAll = false

    let urls: [URL]
    var onClose: (() -> Void)?

    init(urls: [URL]) {
        self.urls = urls
        scan()
    }

    func scan() {
        isLoading = true
        let inputURLs = urls
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var found: [QRCodeResult] = []
            var errs: [String] = []

            for url in inputURLs {
                if url.pathExtension.lowercased() == "pdf" {
                    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
                        errs.append("\(url.lastPathComponent): Could not read PDF.")
                        continue
                    }
                    for pageIdx in 0..<doc.pageCount {
                        guard let page = doc.page(at: pageIdx) else { continue }
                        let rect = page.bounds(for: .mediaBox)
                        let scale: CGFloat = 2.0
                        let w = max(1, Int(rect.width * scale))
                        let h = max(1, Int(rect.height * scale))
                        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                              let ctx = CGContext(
                                  data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                              )
                        else { continue }
                        ctx.setFillColor(NSColor.white.cgColor)
                        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                        ctx.scaleBy(x: scale, y: scale)
                        page.draw(with: .mediaBox, to: ctx)
                        if let cg = ctx.makeImage() {
                            found.append(contentsOf: Self.detectBarcodes(in: cg, sourceName: url.lastPathComponent, page: pageIdx + 1))
                        }
                    }
                } else if let nsImg = NSImage(contentsOf: url),
                          let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    found.append(contentsOf: Self.detectBarcodes(in: cg, sourceName: url.lastPathComponent, page: nil))
                } else {
                    errs.append("\(url.lastPathComponent): Could not read image.")
                }
            }

            DispatchQueue.main.async {
                self?.results = found
                self?.errors = errs
                self?.isLoading = false
            }
        }
    }

    private static func detectBarcodes(in cgImage: CGImage, sourceName: String, page: Int?) -> [QRCodeResult] {
        var detected: [QRCodeResult] = []
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        for obs in request.results ?? [] {
            guard let payload = obs.payloadStringValue, !payload.isEmpty else { continue }
            detected.append(
                QRCodeResult(
                    sourceName: sourceName,
                    page: page,
                    symbology: obs.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: ""),
                    text: payload
                )
            )
        }
        return detected
    }

    func copy(_ item: QRCodeResult) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        copiedID = item.id
        copiedAll = false
    }

    func copyAll() {
        let all = results.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(all, forType: .string)
        copiedAll = true
    }
}

struct QRCodeResultsView: View {
    @ObservedObject var model: QRCodeResultsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(nsColor: NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1)))
                Text("QR Code & Barcode Results")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !model.results.isEmpty {
                    Button(model.copiedAll ? "Copied All ✓" : "Copy All") {
                        model.copyAll()
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            if model.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading QR codes…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if model.results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No QR codes found")
                        .font(.system(size: 13, weight: .medium))
                    if !model.errors.isEmpty {
                        Text(model.errors.joined(separator: "\n"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.results) { item in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.sourceName)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        if let p = item.page {
                                            Text("Page \(p)")
                                                .font(.system(size: 10, weight: .medium))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.secondary.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                        Text(item.symbology)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Text(item.text)
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                if let url = URL(string: item.text),
                                   let scheme = url.scheme?.lowercased(),
                                   scheme == "http" || scheme == "https" {
                                    Button("Open") {
                                        NSWorkspace.shared.open(url)
                                    }
                                    .controlSize(.small)
                                }
                                Button(model.copiedID == item.id ? "Copied ✓" : "Copy") {
                                    model.copy(item)
                                }
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("Close") {
                    model.onClose?()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}

final class QRCodeResultsWindowController: NSWindowController {
    private let model: QRCodeResultsModel

    init(urls: [URL]) {
        self.model = QRCodeResultsModel(urls: urls)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "QR Code Results"
        window.titlebarAppearsTransparent = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: window)
        model.onClose = { [weak self] in
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: QRCodeResultsView(model: model))
        window.contentViewController = hosting
        window.setContentSize(NSSize(
            width: max(440, hosting.view.fittingSize.width),
            height: max(280, hosting.view.fittingSize.height)
        ))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func show() {
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - File Tool Options Window (matching Tangerine's FileToolOptionsWindowController at 0x1001cd43c)

final class FileToolOptionsModel: ObservableObject {
    let urls: [URL]
    let tool: FileTool
    let imagePixelSize: CGSize?
    @Published var options = FileToolOptions()
    @Published var statusMessage: String = ""

    var onApply: (([URL], FileTool, FileToolOptions) -> Void)?
    var onCancel: (() -> Void)?

    init(urls: [URL], tool: FileTool) {
        self.urls = urls
        self.tool = tool
        imagePixelSize = Self.pixelSize(of: urls.first)
        if tool == .organizePDF, let first = urls.first, let doc = PDFDocument(url: first) {
            options.pdfPageOrder = Array(0..<doc.pageCount)
        }
        if tool == .annotateImage {
            options.annotations = [
                ImageAnnotation(kind: .arrow, startX: 0.20, startY: 0.25, endX: 0.55, endY: 0.60, text: "Highlight")
            ]
        }
    }

    func autoDetectFaces() {
        guard let first = urls.first,
              let nsImg = NSImage(contentsOf: first),
              let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let req = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([req])
        let faces = (req.results ?? []).map { obs in
            RedactionRectangle(
                x: obs.boundingBox.origin.x,
                y: obs.boundingBox.origin.y,
                width: obs.boundingBox.size.width,
                height: obs.boundingBox.size.height
            )
        }
        if faces.isEmpty {
            statusMessage = "No faces detected — add a box manually."
        } else {
            options.redactions = faces
            statusMessage = "Detected \(faces.count) face(s)."
        }
    }

    func autoDetectTextRegions() {
        guard let first = urls.first,
              let nsImg = NSImage(contentsOf: first),
              let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .fast
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([req])
        let boxes = (req.results ?? []).map { obs in
            RedactionRectangle(
                x: obs.boundingBox.origin.x,
                y: obs.boundingBox.origin.y,
                width: obs.boundingBox.size.width,
                height: obs.boundingBox.size.height
            )
        }
        if boxes.isEmpty {
            statusMessage = "No text regions detected."
        } else {
            options.redactions = boxes
            statusMessage = "Detected \(boxes.count) text region(s)."
        }
    }

    /// Reason Apply is blocked, or nil when the tool has what it needs.
    var applyBlockedHint: String? {
        switch tool {
        case .redactImage where options.redactions.isEmpty:
            return "Add or detect at least one area to redact."
        case .annotateImage where options.annotations.isEmpty:
            return "Add at least one annotation."
        case .organizePDF where options.pdfPageOrder.isEmpty:
            return "Keep at least one page."
        default:
            return nil
        }
    }

    /// Sets the crop to the largest centered area with the given width/height ratio.
    func applyCenteredCrop(aspect: Double) {
        guard let size = imagePixelSize, size.width > 0, size.height > 0 else { return }
        var cropW = size.width
        var cropH = size.height
        if size.width / size.height > aspect {
            cropW = size.height * aspect
        } else {
            cropH = size.width / aspect
        }
        options.cropX = (size.width - cropW) / (2 * size.width)
        options.cropY = (size.height - cropH) / (2 * size.height)
        options.cropWidth = cropW / size.width
        options.cropHeight = cropH / size.height
    }

    private static func pixelSize(of url: URL?) -> CGSize? {
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        else { return nil }
        // EXIF orientations 5-8 are rotated 90°; the engine loads upright, so swap dimensions.
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }
}

struct FileToolOptionsView: View {
    @ObservedObject var model: FileToolOptionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: model.tool.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(nsColor: NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.tool.fullTitle)
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.urls.count == 1
                         ? model.urls[0].lastPathComponent
                         : "\(model.urls.count) files selected — settings apply to all")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            Group {
                switch model.tool {
                case .compress:
                    compressEditor
                case .editImage:
                    imageAdjustmentEditor
                case .frameImage:
                    frameImageEditor
                case .cropImage, .cropVideo:
                    cropEditor
                case .annotateImage:
                    annotationEditor
                case .createCollage:
                    collageEditor
                case .redactImage:
                    redactionEditor
                case .trimVideo, .trimAudio:
                    trimEditor
                case .changeVideoSpeed:
                    speedEditor
                case .normalizeAudio:
                    normalizeEditor
                case .audioChannels:
                    channelsEditor
                case .audioToVideo:
                    visualizerEditor
                case .organizePDF:
                    organizePDFEditor
                default:
                    Text("Ready to run \(model.tool.fullTitle).")
                        .font(.system(size: 12))
                }
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            if let hint = model.applyBlockedHint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    model.onCancel?()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply \(model.tool.title)") {
                    model.onApply?(model.urls, model.tool, model.options)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1)))
                .keyboardShortcut(.defaultAction)
                .disabled(model.applyBlockedHint != nil)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    // MARK: - Specific Tool Editors

    private var compressEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Compression mode", selection: $model.options.compressionTargetMode) {
                ForEach(CompressionTargetMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch model.options.compressionTargetMode {
            case .preset:
                Picker("Strength", selection: $model.options.imageCompression.strength) {
                    ForEach(ImageCompressionStrength.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                Text(model.options.imageCompression.strength.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            case .percentage:
                HStack {
                    Text("File size reduction")
                    Slider(value: $model.options.compressionReductionPercentage, in: 10...90, step: 5)
                    Text("\(Int(model.options.compressionReductionPercentage))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            case .fileSize:
                HStack {
                    Text("Target maximum size (KB)")
                    Spacer()
                    TextField("KB", value: $model.options.targetSizeKB, format: .number)
                        .frame(width: 100)
                }
            }

            Picker("Dimensions", selection: $model.options.imageCompression.size) {
                ForEach(ImageCompressionSize.allCases) { sz in
                    Text(sz.title).tag(sz)
                }
            }
        }
    }

    private var imageAdjustmentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            sliderRow("Exposure", value: $model.options.imageAdjustments.exposure, range: -2.0...2.0)
            sliderRow("Brightness", value: $model.options.imageAdjustments.brightness, range: -0.4...0.4)
            sliderRow("Contrast", value: $model.options.imageAdjustments.contrast, range: 0.5...1.6)
            sliderRow("Saturation", value: $model.options.imageAdjustments.saturation, range: 0.0...2.0)
            sliderRow("Temperature (K)", value: $model.options.imageAdjustments.temperature, range: 3500...9500)
            sliderRow("Sharpness", value: $model.options.imageAdjustments.sharpness, range: 0.0...2.0)
            sliderRow("Vignette", value: $model.options.imageAdjustments.vignette, range: 0.0...2.0)
            sliderRow("Blur", value: $model.options.imageAdjustments.blur, range: 0.0...15.0)
            HStack {
                Spacer()
                Button("Reset Adjustments") {
                    model.options.imageAdjustments = ImageAdjustments()
                }
                .controlSize(.small)
            }
        }
    }

    private var frameImageEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Background preset", selection: $model.options.imageFrame.background) {
                ForEach(FrameBackgroundPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            Picker("Canvas aspect ratio", selection: $model.options.imageFrame.canvasRatio) {
                ForEach(FrameCanvasRatio.allCases) { ratio in
                    Text(ratio.title).tag(ratio)
                }
            }
            sliderRow("Padding (px)", value: $model.options.imageFrame.padding, range: 12...140)
            sliderRow("Corner radius", value: $model.options.imageFrame.cornerRadius, range: 0...48)
            sliderRow("Shadow radius", value: $model.options.imageFrame.shadowRadius, range: 0...60)
        }
    }

    private var cropEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Preset:")
                    .font(.system(size: 11, weight: .medium))
                Button("Center 80%") {
                    model.options.cropX = 0.10; model.options.cropY = 0.10
                    model.options.cropWidth = 0.80; model.options.cropHeight = 0.80
                }
                .controlSize(.small)
                Button("Square 1:1") {
                    model.applyCenteredCrop(aspect: 1)
                }
                .controlSize(.small)
                .disabled(model.imagePixelSize == nil)
                Button("16:9") {
                    model.applyCenteredCrop(aspect: 16.0 / 9.0)
                }
                .controlSize(.small)
                .disabled(model.imagePixelSize == nil)
            }
            sliderRow("Left Offset", value: $model.options.cropX, range: 0.0...0.85)
            sliderRow("Bottom Offset", value: $model.options.cropY, range: 0.0...0.85)
            sliderRow("Width Share", value: $model.options.cropWidth, range: 0.10...1.0)
            sliderRow("Height Share", value: $model.options.cropHeight, range: 0.10...1.0)
        }
    }

    private var annotationEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(AnnotationKind.allCases) { kind in
                    Button {
                        let idx = model.options.annotations.count + 1
                        let offset = Double(idx % 5) * 0.08
                        model.options.annotations.append(
                            ImageAnnotation(
                                kind: kind,
                                startX: 0.18 + offset,
                                startY: 0.22 + offset,
                                endX: min(0.88, 0.48 + offset),
                                endY: min(0.85, 0.52 + offset),
                                text: "Callout \(idx)",
                                number: idx
                            )
                        )
                    } label: {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                    .controlSize(.small)
                }
            }

            if model.options.annotations.isEmpty {
                Text("Click a tool above to add an annotation.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach($model.options.annotations) { $ann in
                            HStack(spacing: 8) {
                                Image(systemName: ann.kind.symbolName)
                                    .frame(width: 18)
                                Text(ann.kind.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 68, alignment: .leading)
                                if ann.kind == .text {
                                    TextField("Text", text: $ann.text)
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                } else {
                                    Slider(value: $ann.endX, in: 0.1...0.95)
                                }
                                Button {
                                    model.options.annotations.removeAll { $0.id == ann.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
    }

    private var collageEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Layout style", selection: $model.options.collage.style) {
                ForEach(CollageStyle.allCases) { st in
                    Text(st.title).tag(st)
                }
            }
            .pickerStyle(.segmented)

            Stepper("Columns: \(model.options.collage.columns)", value: $model.options.collage.columns, in: 1...6)
            Picker("Background", selection: $model.options.collage.background) {
                ForEach(CollageBackground.allCases) { bg in
                    Text(bg.title).tag(bg)
                }
            }
            sliderRow("Spacing (px)", value: $model.options.collage.spacing, range: 0...48)
            sliderRow("Padding (px)", value: $model.options.collage.padding, range: 0...64)
            sliderRow("Corner radius", value: $model.options.collage.cornerRadius, range: 0...36)
        }
    }

    private var redactionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Redaction style", selection: $model.options.redactionStyle) {
                ForEach(RedactionStyle.allCases) { st in
                    Text(st.title).tag(st)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button("Auto-Detect Faces") {
                    model.autoDetectFaces()
                }
                .controlSize(.small)

                Button("Auto-Detect Text") {
                    model.autoDetectTextRegions()
                }
                .controlSize(.small)

                Button("+ Add Box") {
                    model.options.redactions.append(
                        RedactionRectangle(x: 0.20, y: 0.30, width: 0.60, height: 0.25)
                    )
                }
                .controlSize(.small)

                if !model.options.redactions.isEmpty {
                    Button("Clear") {
                        model.options.redactions.removeAll()
                    }
                    .controlSize(.small)
                }
            }

            Text("\(model.options.redactions.count) redaction region(s) active. Blur softens details; Solid completely covers sensitive areas.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var trimEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRow("Start (sec)", value: $model.options.trimStartSeconds, range: 0...300)
            sliderRow("Duration (sec)", value: $model.options.trimDurationSeconds, range: 0.5...600)
            if model.tool == .trimAudio {
                Toggle("Trim silent ends automatically", isOn: $model.options.autoTrimSilence)
                if model.options.autoTrimSilence {
                    sliderRow("Silence threshold (dB)", value: $model.options.silenceThresholdDB, range: -80...(-10))
                }
            }
        }
    }

    private var speedEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRow("Playback speed (×)", value: $model.options.playbackSpeed, range: 0.25...4.0)
            HStack(spacing: 8) {
                ForEach([0.5, 0.75, 1.25, 1.5, 2.0, 3.0], id: \.self) { preset in
                    Button("\(String(format: "%.2g", preset))×") {
                        model.options.playbackSpeed = preset
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var normalizeEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRow("Target Loudness (LUFS)", value: $model.options.normalizationTargetLoudness, range: -30...(-8))
            sliderRow("Loudness Range (LU)", value: $model.options.normalizationLoudnessRange, range: 1...25)
            sliderRow("True Peak (dBTP)", value: $model.options.normalizationTruePeak, range: -6...0)
            Text("−16 LUFS is a balanced default for spoken audio and music. The true peak limit helps prevent clipping.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var channelsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Output channels", selection: $model.options.audioChannelCount) {
                Text("Mono (1 ch)").tag(1)
                Text("Stereo (2 ch)").tag(2)
            }
            .pickerStyle(.segmented)
            sliderRow("Left channel gain", value: $model.options.audioLeftVolume, range: 0.0...2.0)
            sliderRow("Right channel gain", value: $model.options.audioRightVolume, range: 0.0...2.0)
        }
    }

    private var visualizerEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generates an MP4 video with Tangerine's signature #FF5200 waveform visualization.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
        }
    }

    private var organizePDFEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pages (\(model.options.pdfPageOrder.count)): rotate or remove pages before saving.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(model.options.pdfPageOrder.enumerated()), id: \.element) { idx, pageNum in
                        HStack {
                            Text("Page \(pageNum + 1)")
                                .font(.system(size: 12, weight: .medium))
                            if let rot = model.options.pdfPageRotations[pageNum], rot != 0 {
                                Text("Rotated \(rot)°")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Rotate 90°") {
                                let cur = model.options.pdfPageRotations[pageNum] ?? 0
                                model.options.pdfPageRotations[pageNum] = (cur + 90) % 360
                            }
                            .controlSize(.small)
                            if model.options.pdfPageOrder.count > 1 {
                                Button("Remove") {
                                    model.options.pdfPageOrder.remove(at: idx)
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5))
                .frame(width: 138, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
        }
    }
}

final class FileToolOptionsWindowController: NSWindowController {
    private let model: FileToolOptionsModel

    init(
        urls: [URL],
        tool: FileTool,
        onApply: @escaping ([URL], FileTool, FileToolOptions) -> Void
    ) {
        let model = FileToolOptionsModel(urls: urls, tool: tool)
        self.model = model

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = tool.fullTitle
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        model.onApply = { [weak self] urls, tool, opts in
            self?.window?.close()
            onApply(urls, tool, opts)
        }
        model.onCancel = { [weak self] in
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: FileToolOptionsView(model: model))
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(
            width: max(460, hosting.view.fittingSize.width),
            height: max(340, hosting.view.fittingSize.height)
        ))
        panel.center()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func show() {
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
