import AppKit
import ImageIO
import SwiftUI

// MARK: - Crop model

enum CropAspect: CaseIterable, Identifiable {
    case free, square, wide, tall, standard, portrait

    var id: Self { self }

    var title: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .wide: return "16:9"
        case .tall: return "9:16"
        case .standard: return "4:3"
        case .portrait: return "3:4"
        }
    }

    /// Pixel width / pixel height, or nil for an unconstrained crop.
    var ratio: Double? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .wide: return 16.0 / 9.0
        case .tall: return 9.0 / 16.0
        case .standard: return 4.0 / 3.0
        case .portrait: return 3.0 / 4.0
        }
    }
}

enum CropHandle {
    case move, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

    var movesLeft: Bool { [.left, .topLeft, .bottomLeft].contains(self) }
    var movesRight: Bool { [.right, .topRight, .bottomRight].contains(self) }
    var movesTop: Bool { [.top, .topLeft, .topRight].contains(self) }
    var movesBottom: Bool { [.bottom, .bottomLeft, .bottomRight].contains(self) }
    var isCorner: Bool { [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(self) }

    var cursor: NSCursor {
        switch self {
        case .move: return .openHand
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }
}

enum CropGeometry {
    /// Smallest crop edge, in pixels.
    static let minimumPixels: CGFloat = 16

    /// Applies a drag of (dx, dy) — normalized to the image — to `start`.
    /// `ratio` is the locked normalized width/height ratio, or nil for free resizing.
    static func adjust(_ start: CGRect, handle: CropHandle, dx: CGFloat, dy: CGFloat,
                       ratio: CGFloat?, minW: CGFloat, minH: CGFloat) -> CGRect {
        if handle == .move {
            return CGRect(
                x: min(max(0, start.minX + dx), 1 - start.width),
                y: min(max(0, start.minY + dy), 1 - start.height),
                width: start.width, height: start.height
            )
        }

        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if handle.movesLeft { minX = min(max(0, start.minX + dx), maxX - minW) }
        if handle.movesRight { maxX = max(min(1, start.maxX + dx), minX + minW) }
        if handle.movesTop { minY = min(max(0, start.minY + dy), maxY - minH) }
        if handle.movesBottom { maxY = max(min(1, start.maxY + dy), minY + minH) }

        guard let k = ratio else {
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        var w = maxX - minX
        var h = maxY - minY
        let floorW = max(minW, minH * k)

        if handle.isCorner {
            // The opposite corner stays fixed.
            let ax = handle.movesLeft ? start.maxX : start.minX
            let ay = handle.movesTop ? start.maxY : start.minY
            let availW = handle.movesLeft ? ax : 1 - ax
            let availH = handle.movesTop ? ay : 1 - ay
            w = min(max(w, h * k, floorW), availW, availH * k)
            h = w / k
            return CGRect(x: handle.movesLeft ? ax - w : ax,
                          y: handle.movesTop ? ay - h : ay,
                          width: w, height: h)
        }

        if handle == .left || handle == .right {
            // Width follows the edge; height follows the ratio, centered on the old center.
            w = max(w, floorW)
            h = w / k
            if h > 1 { h = 1; w = k }
            let x = handle == .left ? start.maxX - w : start.minX
            let y = min(max(0, start.midY - h / 2), 1 - h)
            return CGRect(x: x, y: y, width: w, height: h)
        }

        h = max(h, floorW / k)
        w = h * k
        if w > 1 { w = 1; h = 1 / k }
        let y = handle == .top ? start.maxY - h : start.minY
        let x = min(max(0, start.midX - w / 2), 1 - w)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Largest rect with normalized ratio `k`, centered on `center`, inside the unit square.
    static func largest(ratio k: CGFloat, centeredOn center: CGPoint) -> CGRect {
        var w: CGFloat = 1
        var h = w / k
        if h > 1 { h = 1; w = k }
        let x = min(max(0, center.x - w / 2), 1 - w)
        let y = min(max(0, center.y - h / 2), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

extension FileToolOptionsModel {
    static let fullCrop = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Normalized crop rectangle, origin top-left.
    var cropRect: CGRect {
        get { CGRect(x: options.cropX, y: options.cropY, width: options.cropWidth, height: options.cropHeight) }
        set {
            options.cropX = Double(newValue.minX)
            options.cropY = Double(newValue.minY)
            options.cropWidth = Double(newValue.width)
            options.cropHeight = Double(newValue.height)
        }
    }

    /// Locked width/height ratio in normalized units (pixel ratio corrected for the image's shape).
    var normalizedCropRatio: CGFloat? {
        guard let r = cropAspect.ratio, let size = mediaPixelSize, size.width > 0 else { return nil }
        return CGFloat(r) * size.height / size.width
    }

    func selectCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        guard let k = normalizedCropRatio else { return }
        let rect = cropRect
        cropRect = CropGeometry.largest(ratio: k, centeredOn: CGPoint(x: rect.midX, y: rect.midY))
    }

    func resetCrop() {
        cropAspect = .free
        cropRect = Self.fullCrop
    }

    var cropPixelWidth: Int {
        guard let size = mediaPixelSize else { return 0 }
        return Int((cropRect.width * size.width).rounded())
    }

    var cropPixelHeight: Int {
        guard let size = mediaPixelSize else { return 0 }
        return Int((cropRect.height * size.height).rounded())
    }

    /// Sets the crop size in pixels, keeping its center and the locked ratio.
    func setCropPixels(width: Int? = nil, height: Int? = nil) {
        guard let size = mediaPixelSize, size.width > 0, size.height > 0 else { return }
        let rect = cropRect
        var w = width.map { CGFloat($0) / size.width } ?? rect.width
        var h = height.map { CGFloat($0) / size.height } ?? rect.height
        if let k = normalizedCropRatio {
            if width != nil { h = w / k } else if height != nil { w = h * k }
            let scale = min(1, 1 / w, 1 / h)
            w *= scale
            h *= scale
        }
        w = min(max(w, CropGeometry.minimumPixels / size.width), 1)
        h = min(max(h, CropGeometry.minimumPixels / size.height), 1)
        cropRect = CGRect(
            x: min(max(0, rect.midX - w / 2), 1 - w),
            y: min(max(0, rect.midY - h / 2), 1 - h),
            width: w, height: h
        )
    }

    /// Window content size that fits the preview without distorting it.
    var cropWindowSize: CGSize {
        // Until a video frame loads, reserve a 16:9 canvas.
        let media = mediaPixelSize ?? CGSize(width: 1280, height: 720)
        let scale = min(720 / media.width, 480 / media.height, 4)
        let canvas = CGSize(width: media.width * scale, height: max(200, media.height * scale))
        return CGSize(
            width: max(500, canvas.width + 40).rounded(),
            height: (52 + canvas.height + 32 + 96 + 60).rounded()
        )
    }

    /// Loads an upright preview and the pixel size the engine will crop.
    func loadCropPreview() {
        guard let url = urls.first else { return }
        if tool == .cropVideo {
            let ffmpeg = ToolLocator.ffmpeg()
            guard !ffmpeg.isEmpty else {
                cropPreviewFailed = true
                statusMessage = "Install ffmpeg to preview and crop video."
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let loaded = FileToolOptionsModel.videoFrame(url: url, ffmpeg: ffmpeg)
                DispatchQueue.main.async { self?.applyLoadedPreview(loaded) }
            }
        } else {
            applyLoadedPreview(Self.imagePreview(url: url))
        }
    }

    private func applyLoadedPreview(_ loaded: (image: CGImage, pixelSize: CGSize)?) {
        guard let loaded else {
            cropPreviewFailed = true
            return
        }
        cropPreview = loaded.image
        if mediaPixelSize == nil { mediaPixelSize = loaded.pixelSize }
    }

    private static func imagePreview(url: URL) -> (image: CGImage, pixelSize: CGSize)? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
            ]
            if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
                return (thumb, CGSize(width: thumb.width, height: thumb.height))
            }
        }
        // Formats ImageIO cannot read (SVG) go through NSImage, like the engine.
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return (cg, CGSize(width: cg.width, height: cg.height))
    }

    /// Extracts one display-oriented frame at full resolution; its size is what ffmpeg's crop sees.
    private static func videoFrame(url: URL, ffmpeg: String) -> (image: CGImage, pixelSize: CGSize)? {
        let frameURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("daisy-crop-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: frameURL) }
        for seek in ["1", "0"] {
            let res = ToolRunner.run(
                ffmpeg,
                arguments: ["-y", "-ss", seek, "-i", url.path, "-frames:v", "1", frameURL.path],
                timeout: 30
            )
            guard res.succeeded,
                  let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
                  let full = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { continue }
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
            ]
            let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) ?? full
            return (preview, CGSize(width: full.width, height: full.height))
        }
        return nil
    }
}

// MARK: - Crop view (matches Tangerine's Crop Image window)

private let cropAccent = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1.0))

struct CropEditorView: View {
    @ObservedObject var model: FileToolOptionsModel
    @State private var dragStart: CGRect?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            GeometryReader { geo in
                canvas(in: geo.size)
            }
            .padding(16)
            controls
            Divider().opacity(0.5)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CropWindowMaterial().ignoresSafeArea())
    }

    private var header: some View {
        ZStack {
            Text(model.tool.fullTitle)
                .font(.system(size: 17, weight: .semibold))
            HStack {
                Button {
                    model.onCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Cancel")
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    @ViewBuilder
    private func canvas(in available: CGSize) -> some View {
        if let image = model.cropPreview, let media = model.mediaPixelSize, media.width > 0, media.height > 0 {
            let scale = min(available.width / media.width, available.height / media.height)
            let display = CGSize(width: media.width * scale, height: media.height * scale)
            cropSurface(image: image, display: display)
                .frame(width: display.width, height: display.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                if model.cropPreviewFailed {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(model.statusMessage.isEmpty ? "Preview unavailable." : model.statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Loading preview…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cropSurface(image: CGImage, display: CGSize) -> some View {
        let r = model.cropRect
        let box = CGRect(x: r.minX * display.width, y: r.minY * display.height,
                         width: r.width * display.width, height: r.height * display.height)
        return ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: display.width, height: display.height)

            // Dim everything outside the crop.
            Path { p in
                p.addRect(CGRect(origin: .zero, size: display))
                p.addRect(box)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            if dragStart != nil {
                thirdsGrid(in: box)
            }

            Rectangle()
                .stroke(cropAccent, lineWidth: 2)
                .frame(width: box.width, height: box.height)
                .offset(x: box.minX, y: box.minY)
                .allowsHitTesting(false)

            // Move area (inside the box, under the handles).
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(0, box.width - 20), height: max(0, box.height - 20))
                .offset(x: box.minX + 10, y: box.minY + 10)
                .gesture(drag(.move, display: display))
                .onHover { hovering in hovering ? NSCursor.openHand.push() : NSCursor.pop() }

            edgeHandle(.top, at: CGPoint(x: box.midX, y: box.minY), display: display)
            edgeHandle(.bottom, at: CGPoint(x: box.midX, y: box.maxY), display: display)
            edgeHandle(.left, at: CGPoint(x: box.minX, y: box.midY), display: display)
            edgeHandle(.right, at: CGPoint(x: box.maxX, y: box.midY), display: display)
            cornerHandle(.topLeft, at: CGPoint(x: box.minX, y: box.minY), display: display)
            cornerHandle(.topRight, at: CGPoint(x: box.maxX, y: box.minY), display: display)
            cornerHandle(.bottomLeft, at: CGPoint(x: box.minX, y: box.maxY), display: display)
            cornerHandle(.bottomRight, at: CGPoint(x: box.maxX, y: box.maxY), display: display)
        }
    }

    private func thirdsGrid(in box: CGRect) -> some View {
        Path { p in
            for i in 1...2 {
                let x = box.minX + box.width * CGFloat(i) / 3
                let y = box.minY + box.height * CGFloat(i) / 3
                p.move(to: CGPoint(x: x, y: box.minY)); p.addLine(to: CGPoint(x: x, y: box.maxY))
                p.move(to: CGPoint(x: box.minX, y: y)); p.addLine(to: CGPoint(x: box.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.55), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func edgeHandle(_ handle: CropHandle, at point: CGPoint, display: CGSize) -> some View {
        let horizontal = handle == .top || handle == .bottom
        return RoundedRectangle(cornerRadius: 3)
            .fill(cropAccent)
            .frame(width: horizontal ? 26 : 6, height: horizontal ? 6 : 26)
            .frame(width: horizontal ? 44 : 20, height: horizontal ? 20 : 44)
            .contentShape(Rectangle())
            .position(point)
            .gesture(drag(handle, display: display))
            .onHover { hovering in hovering ? handle.cursor.push() : NSCursor.pop() }
    }

    private func cornerHandle(_ handle: CropHandle, at point: CGPoint, display: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(cropAccent)
            .frame(width: 13, height: 13)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .position(point)
            .gesture(drag(handle, display: display))
            .onHover { hovering in hovering ? handle.cursor.push() : NSCursor.pop() }
    }

    private func drag(_ handle: CropHandle, display: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = model.cropRect
                    if handle == .move { NSCursor.closedHand.push() }
                }
                guard let start = dragStart, let media = model.mediaPixelSize else { return }
                model.cropRect = CropGeometry.adjust(
                    start,
                    handle: handle,
                    dx: value.translation.width / display.width,
                    dy: value.translation.height / display.height,
                    ratio: model.normalizedCropRatio,
                    minW: min(1, CropGeometry.minimumPixels / media.width),
                    minH: min(1, CropGeometry.minimumPixels / media.height)
                )
            }
            .onEnded { _ in
                if handle == .move { NSCursor.pop() }
                dragStart = nil
            }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Aspect ratio")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                aspectPicker
            }
            HStack(spacing: 8) {
                dimensionField("W", value: Binding(
                    get: { model.cropPixelWidth },
                    set: { model.setCropPixels(width: $0) }
                ))
                dimensionField("H", value: Binding(
                    get: { model.cropPixelHeight },
                    set: { model.setCropPixels(height: $0) }
                ))
                Text("px")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                if model.urls.count > 1 {
                    Text("Applies to \(model.urls.count) files")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .disabled(model.mediaPixelSize == nil)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(height: 96)
    }

    private var aspectPicker: some View {
        HStack(spacing: 2) {
            ForEach(CropAspect.allCases) { aspect in
                let selected = model.cropAspect == aspect
                Button {
                    model.selectCropAspect(aspect)
                } label: {
                    Text(aspect.title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? .white : .primary.opacity(0.75))
                        .frame(minWidth: 44)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? cropAccent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.mediaPixelSize == nil && aspect != .free)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
    }

    private func dimensionField(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            TextField(label, value: value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(width: 78)
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset") { model.resetCrop() }
                .buttonStyle(CropFooterButtonStyle(prominent: false))
            Spacer()
            Button("Apply") { model.onApply?(model.urls, model.tool, model.options) }
                .buttonStyle(CropFooterButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.mediaPixelSize == nil)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }
}

private struct CropFooterButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .medium))
            .foregroundColor(prominent ? .white : .primary.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? cropAccent : Color.primary.opacity(0.08))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

/// Translucent window material behind the crop editor.
private struct CropWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
