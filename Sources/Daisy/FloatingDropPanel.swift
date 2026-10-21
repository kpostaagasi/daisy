// Daisy — ConversionOverlayController (radial fan panel) and OperationProgressController inspired by Tangerine.
import AppKit
import Combine
import QuartzCore

// MARK: - Conversion Overlay Panel (matching Tangerine's ConversionOverlayPanel at 0x100061e24)

final class ConversionOverlayPanel: NSPanel {
    var onEscapePressed: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscapePressed?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - FloatingDropPanel (ConversionOverlayController at 0x1000621ac)

final class FloatingDropPanel {
    var onActionSelected: (([URL], ConversionFanAction) -> Void)?
    var onDismiss: (() -> Void)?

    private(set) var isDragInside = false
    private var panel: ConversionOverlayPanel?
    private var fanView: FanPanelView?
    private var clickOutsideMonitor: Any?
    private var keyMonitors: [Any] = []
    private var pendingFileSelection: NSOpenPanel?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    var containsMouseLocation: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    init(onActionSelected: @escaping ([URL], ConversionFanAction) -> Void) {
        self.onActionSelected = onActionSelected
        setupPanel()
    }

    private func setupPanel() {
        let size = FanPanelView.defaultSize // 372 × 372
        let panel = ConversionOverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let fanView = FanPanelView { [weak self] files, action in
            self?.dismiss()
            self?.onActionSelected?(files, action)
        }
        fanView.onDismissRequested = { [weak self] in
            self?.dismiss()
        }
        fanView.onFileSelectionRequested = { [weak self] action in
            self?.dismiss()
            DispatchQueue.main.async { self?.presentFileSelection(for: action) }
        }
        fanView.onDragStateChanged = { [weak self] inside in
            self?.isDragInside = inside
        }
        panel.onEscapePressed = { [weak self] in
            self?.dismiss()
        }
        panel.contentView = fanView

        self.panel = panel
        self.fanView = fanView
    }

    /// Shows the radial fan centered at the current mouse cursor (or switches mode if already visible).
    func show(urls: [URL] = [], mode: ConversionFanMode = .conversions, atMouseLocation: Bool = true) {
        guard let panel, let fanView else { return }

        let alreadyVisible = panel.isVisible
        if !alreadyVisible || !urls.isEmpty {
            if atMouseLocation {
                positionNearMouse(panel: panel)
            } else {
                positionNearTopRight(panel: panel)
            }
        }

        if alreadyVisible, mode != fanView.fanMode {
            FanHaptics.perform(.modeChange)
        } else if !alreadyVisible, !urls.isEmpty {
            FanHaptics.perform(.appear)
        }
        fanView.configure(urls: urls, mode: mode, animated: true)

        if !alreadyVisible {
            panel.alphaValue = 1.0
            panel.orderFrontRegardless()
            installClickOutsideMonitor()
            installKeyMonitors()
        }
    }

    func dismiss() {
        removeClickOutsideMonitor()
        removeKeyMonitors()
        guard let panel, panel.isVisible else { return }
        isDragInside = false
        panel.orderOut(nil)
        panel.alphaValue = 0.0
        onDismiss?()
    }

    /// Runs after the fan is gone: activates Daisy and shows a non-modal open panel so it appears over fullscreen apps.
    private func presentFileSelection(for action: ConversionFanAction) {
        NSApp.activate(ignoringOtherApps: true)
        let openPanel = NSOpenPanel()
        openPanel.title = action.detailTitle
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = (action == .float || action == .copy || action == .move || action == .copyPath || action == .openTerminal)
        openPanel.allowsMultipleSelection = true
        openPanel.level = .modalPanel
        openPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pendingFileSelection = openPanel
        openPanel.begin { [weak self] response in
            guard let self else { return }
            self.pendingFileSelection = nil
            guard response == .OK, !openPanel.urls.isEmpty else { return }
            let urls = openPanel.urls
            // The Tools fan shows one Crop petal; picked videos go to the video crop.
            if case .fileTool(.cropImage) = action, FileTool.cropVideo.supports(urls: urls) {
                self.onActionSelected?(urls, .fileTool(.cropVideo))
            } else {
                self.onActionSelected?(urls, action)
            }
        }
    }

    private func positionNearMouse(panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size

        var originX = mouse.x - size.width * 0.5
        var originY = mouse.y - size.height * 0.5
        originX = max(visible.minX + 8, min(originX, visible.maxX - size.width - 8))
        originY = max(visible.minY + 8, min(originY, visible.maxY - size.height - 8))
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func positionNearTopRight(panel: NSPanel) {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 36,
            y: visible.maxY - size.height - 28
        )
        panel.setFrameOrigin(origin)
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let mouse = NSEvent.mouseLocation
            if !panel.frame.contains(mouse) {
                self.dismiss()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
    }

    private func installKeyMonitors() {
        removeKeyMonitors()
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.isVisible else { return event }
            self.dismiss()
            return nil
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            self?.dismiss()
        }
        keyMonitors = [localMonitor, globalMonitor].compactMap { $0 }
    }

    private func removeKeyMonitors() {
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        keyMonitors.removeAll()
    }
}

// MARK: - Orange Indeterminate / Determinate Progress View (matching Tangerine at 0x1002a12dc)

final class OrangeIndeterminateProgressView: NSView {
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    var fractionCompleted: Double? {
        didSet { updateBar() }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 6)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 3

        trackLayer.masksToBounds = true
        trackLayer.cornerRadius = 3
        trackLayer.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        layer?.addSublayer(trackLayer)

        fillLayer.cornerRadius = 3
        fillLayer.backgroundColor = NSColor(srgbRed: 1.0, green: 0.3215, blue: 0.0, alpha: 1.0).cgColor
        trackLayer.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func layout() {
        super.layout()
        trackLayer.frame = bounds
        updateBar()
    }

    private func updateBar() {
        fillLayer.removeAnimation(forKey: "indeterminate")
        let w = bounds.width
        let h = bounds.height
        guard w > 0 else { return }

        if let frac = fractionCompleted {
            let clamped = max(0.06, min(1.0, frac))
            fillLayer.frame = CGRect(x: 0, y: 0, width: w * clamped, height: h)
        } else {
            let barW = max(48, w * 0.35)
            fillLayer.frame = CGRect(x: -barW, y: 0, width: barW, height: h)
            let anim = CABasicAnimation(keyPath: "position.x")
            anim.fromValue = -barW * 0.5
            anim.toValue = w + barW * 0.5
            anim.duration = 1.05
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fillLayer.add(anim, forKey: "indeterminate")
        }
    }
}

// MARK: - Operation Progress Window Controller (matching Tangerine at 0x1002a3d54)

final class OperationProgressWindowController: NSWindowController {
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Operation in progress")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressView = OrangeIndeterminateProgressView(frame: .zero)
    private let closeButton = NSButton()
    private let errorScroll = NSScrollView()
    private let errorTextView = NSTextView()

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)
        buildUI(in: panel)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    private func buildUI(in panel: NSPanel) {
        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 320, height: 92))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 18
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        panel.contentView = glass

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 16, y: 56, width: 256, height: 18)
        glass.addSubview(titleLabel)

        if let closeImg = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close") {
            closeButton.image = closeImg
        }
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.frame = NSRect(x: 284, y: 55, width: 20, height: 20)
        glass.addSubview(closeButton)

        statusLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.frame = NSRect(x: 16, y: 34, width: 288, height: 16)
        glass.addSubview(statusLabel)

        progressView.frame = NSRect(x: 16, y: 16, width: 288, height: 6)
        glass.addSubview(progressView)

        errorTextView.isEditable = false
        errorTextView.isSelectable = true
        errorTextView.drawsBackground = false
        errorTextView.font = .systemFont(ofSize: 11)
        errorTextView.textColor = .labelColor
        errorTextView.isVerticallyResizable = true
        errorTextView.isHorizontallyResizable = false
        errorTextView.autoresizingMask = [.width]
        errorTextView.minSize = NSSize(width: 0, height: 0)
        errorTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        errorTextView.textContainer?.widthTracksTextView = true
        errorTextView.textContainer?.heightTracksTextView = false
        errorTextView.textContainer?.containerSize = NSSize(width: 288, height: CGFloat.greatestFiniteMagnitude)
        errorScroll.hasVerticalScroller = true
        errorScroll.drawsBackground = false
        errorScroll.isHidden = true
        errorScroll.frame = NSRect(x: 16, y: 12, width: 288, height: 64)
        errorScroll.documentView = errorTextView
        errorTextView.frame = NSRect(origin: .zero, size: NSSize(width: errorScroll.contentSize.width, height: 64))
        glass.addSubview(errorScroll)
    }

    func showNearCursor() {
        guard let window else { return }
        if !window.isVisible {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let w = window.frame.width
            let h = window.frame.height
            let x = max(visible.minX + 16, min(mouse.x - w * 0.5, visible.maxX - w - 16))
            let y = max(visible.minY + 16, min(mouse.y - h - 24, visible.maxY - h - 16))
            window.setFrameOrigin(NSPoint(x: x, y: y))
            window.orderFrontRegardless()
        }
    }

    func updateProgress(title: String, status: String, fraction: Double?) {
        titleLabel.stringValue = title
        statusLabel.stringValue = status
        progressView.isHidden = false
        progressView.fractionCompleted = fraction
        errorScroll.isHidden = true
    }

    func showFailure(title: String, details: String) {
        guard let window, let glass = window.contentView else { return }
        let expandedHeight: CGFloat = 152
        var frame = window.frame
        frame.origin.y -= (expandedHeight - frame.height)
        frame.size.height = expandedHeight
        window.setFrame(frame, display: true, animate: true)
        glass.frame = NSRect(origin: .zero, size: frame.size)

        titleLabel.stringValue = title
        titleLabel.frame = NSRect(x: 16, y: expandedHeight - 34, width: 256, height: 18)
        closeButton.frame = NSRect(x: 284, y: expandedHeight - 35, width: 20, height: 20)
        statusLabel.stringValue = "Review details below:"
        statusLabel.frame = NSRect(x: 16, y: expandedHeight - 54, width: 288, height: 16)
        progressView.isHidden = true

        errorTextView.string = details
        errorScroll.frame = NSRect(x: 16, y: 14, width: 288, height: expandedHeight - 74)
        errorScroll.isHidden = false
        fitErrorTextView()
        window.orderFrontRegardless()
    }

    /// Pins the text view to the scroll view's visible width and grows its height to fit the wrapped text.
    private func fitErrorTextView() {
        let width = errorScroll.contentSize.width
        let visibleHeight = errorScroll.contentSize.height
        var textHeight: CGFloat = 0
        if let container = errorTextView.textContainer, let layoutManager = errorTextView.layoutManager {
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            textHeight = layoutManager.usedRect(for: container).height + errorTextView.textContainerInset.height * 2
        }
        errorTextView.frame = NSRect(x: 0, y: 0, width: width, height: max(visibleHeight, textHeight))
    }

    @objc private func closeClicked() {
        window?.close()
        onClose?()
    }
}
