// Daisy — the glass drop panel: a central hub with radiating petals.
// Drag files over the panel and the fan opens; drop a file on a petal to
// convert it with the matching target, or on the hub to keep it staged.
import AppKit

/// Root container view of the panel: glass background + fan + status line.
final class FanPanelView: NSView {
    private let background = NSVisualEffectView()
    private let statusLabel = NSTextField(labelWithString: "Drag files here")
    private let fan: FanLayoutView

    init(onConvert: @escaping ([URL], ConversionTarget) -> Void) {
        fan = FanLayoutView(onConvert: onConvert)
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 440, height: 440)))

        wantsLayer = true
        layer?.cornerRadius = 26
        layer?.masksToBounds = true

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 26
        addSubview(background)

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 20, y: 24, width: 400, height: 16)
        addSubview(statusLabel)

        fan.autoresizingMask = []
        fan.onStatus = { [weak self] text in self?.setStatus(text) }
        addSubview(fan)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func layout() {
        super.layout()
        background.frame = bounds

        let size = min(bounds.width, bounds.height)
        let fanSize = size - 64
        let origin = NSPoint(
            x: (bounds.width - fanSize) / 2,
            y: (bounds.height - fanSize) / 2 + 20
        )
        fan.frame = NSRect(origin: origin, size: NSSize(width: fanSize, height: fanSize))
    }

    override var acceptsFirstResponder: Bool { false }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text.isEmpty ? "Drag files here" : text
    }

    func setBusy(_ busy: Bool) {
        fan.setBusy(busy)
    }
}

/// The fan: central hub + radiating glass petals, each a drop target.
final class FanLayoutView: NSView {
    private var onConvert: ([URL], ConversionTarget) -> Void
    private let targets = ConversionTarget.fan
    private var petalViews: [PetalDropView] = []
    private var expanded = false
    private var isBusy = false

    private var stagedFiles: [URL] = []
    private let hub = NSImageView()

    init(onConvert: @escaping ([URL], ConversionTarget) -> Void) {
        self.onConvert = onConvert
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 376, height: 376)))

        wantsLayer = true

        hub.image = NSImage(
            systemSymbolName: "circle.dotted.circle",
            accessibilityDescription: "Daisy"
        )
        hub.contentTintColor = .labelColor
        addSubview(hub)

        for (index, target) in targets.enumerated() {
            let petal = PetalDropView(target: target, index: index) { [weak self] target in
                guard let self else { return }
                let files = self.stagedFilesForDrop()
                self.onConvert(files, target)
                self.expand(false)
            }
            addSubview(petal)
            petalViews.append(petal)
        }
        positionPetals(extended: false, animated: false)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let side = bounds.width
        let hubSize: CGFloat = min(84, side * 0.24)
        hub.frame = NSRect(
            x: (side - hubSize) / 2,
            y: (side - hubSize) / 2,
            width: hubSize,
            height: hubSize
        )
    }

    private func petalAngle(_ index: Int) -> CGFloat {
        let count = petalViews.count
        guard count > 0 else { return 0 }
        // Distributed evenly, starting at the top.
        return .pi / 2 - 2 * .pi * CGFloat((index + count / 2) % count) / CGFloat(count)
    }

    private func positionPetals(extended: Bool, animated: Bool) {
        func apply() {
            let side = bounds.width
            let radius: CGFloat = extended ? side * 0.34 : side * 0.12
            let petalSize: CGFloat = min(84, side * 0.16)
            for (index, petal) in petalViews.enumerated() {
                let angle = petalAngle(index)
                let center = CGPoint(
                    x: side / 2 + cos(angle) * radius,
                    y: side / 2 + sin(angle) * radius
                )
                petal.frame = NSRect(
                    x: center.x - petalSize / 2,
                    y: center.y - petalSize / 2,
                    width: petalSize,
                    height: petalSize
                )
            }
        }
        guard animated else { apply(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            apply()
        }
    }

    // MARK: - Fan state

    func expand(_ extend: Bool) {
        guard expanded != extend else { return }
        expanded = extend
        statusHint()
        positionPetals(extended: extend, animated: true)
    }

    private func statusHint() {
        onStatus?(stagedFiles.isEmpty ? "Drag files here" : "\(stagedFiles.count) file(s) staged")
    }

    var onStatus: ((String) -> Void)?

    private func stagedFilesForDrop() -> [URL] {
        let files = stagedFiles
        stagedFiles = []
        return files
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        expand(true)
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []

        // Hit-test: which petal is under the drop point?
        let point = convert(sender.draggingLocation, from: nil)
        let petal = subviews.last { view in
            view is PetalDropView && view.frame.contains(point)
        } as? PetalDropView

        guard let petal else {
            // Dropped on the hub: stage the files for the next petal click.
            stagedFiles = files
            statusHint()
            expand(false)
            return true
        }

        onConvert(files, petal.conversionTarget)
        statusHintAfterConvert()
        expand(false)
        return files.isEmpty == false
    }

    private func statusHintAfterConvert() {
        onStatus?("Converting…")
    }

    func setBusy(_ busy: Bool) {
        isBusy = busy
        hub.animator().alphaValue = busy ? 0.5 : 1
    }

    func updateStatus(_ text: String) {
        onStatus?(text)
    }
}

/// Glass petal that receives clicks. Drop routing happens centrally in
/// FanLayoutView (hit-testing), so petals only need visual feedback.
final class PetalDropView: NSView {
    let conversionTarget: ConversionTarget
    private let action: (ConversionTarget) -> Void

    init(target: ConversionTarget, index: Int, action: @escaping (ConversionTarget) -> Void) {
        self.conversionTarget = target
        self.action = action

        super.init(frame: NSRect(x: 0, y: 0, width: 84, height: 84))

        let label = NSTextField(labelWithString: target.label)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 30, width: 84, height: 24)
        label.autoresizingMask = [.width]
        addSubview(label)

        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.05).cgColor
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        action(conversionTarget)
        layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.05).cgColor
    }
}
