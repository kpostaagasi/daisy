// Daisy — FloatingFileWindowController ("Float" shelf & edge-attached paperclip tab) + File Actions inspired by Tangerine.
import AppKit
import Combine
import QuickLookThumbnailing
import Quartz

// MARK: - File Action Controllers (matching Tangerine's FileClipboardController, FileMoveAction, TerminalFileAction, AirDropSharingController)

final class FileClipboardController {
    static let shared = FileClipboardController()

    func copyFiles(_ urls: [URL]) throws {
        let localURLs = urls.filter(\.isFileURL)
        guard !localURLs.isEmpty else {
            throw NSError(domain: "Daisy.Clipboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only local files and folders can be copied."])
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.writeObjects(localURLs as [NSURL]) else {
            throw NSError(domain: "Daisy.Clipboard", code: 2, userInfo: [NSLocalizedDescriptionKey: "The files couldn’t be placed on the clipboard."])
        }
    }

    func copyPaths(_ urls: [URL]) throws {
        let localURLs = urls.filter(\.isFileURL)
        guard !localURLs.isEmpty else {
            throw NSError(domain: "Daisy.Clipboard", code: 3, userInfo: [NSLocalizedDescriptionKey: "Only local file and folder paths can be copied."])
        }
        let text = localURLs.map(\.path).joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.setString(text, forType: .string) else {
            throw NSError(domain: "Daisy.Clipboard", code: 4, userInfo: [NSLocalizedDescriptionKey: "The paths couldn’t be placed on the clipboard."])
        }
    }
}

final class FileMoveAction {
    static let shared = FileMoveAction()

    func moveFilesInteractively(_ urls: [URL]) throws -> [URL] {
        let localURLs = urls.filter(\.isFileURL)
        guard !localURLs.isEmpty else {
            throw NSError(domain: "Daisy.FileMove", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only local files and folders can be moved."])
        }

        let panel = NSOpenPanel()
        panel.title = localURLs.count == 1
            ? "Choose a destination folder for \(localURLs[0].lastPathComponent)"
            : "Choose a destination folder for \(localURLs.count) items"
        panel.prompt = "Move Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destinationDir = panel.url else {
            return []
        }

        var moved: [URL] = []
        let fm = FileManager.default
        for src in localURLs {
            if src.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL {
                moved.append(src)
                continue
            }
            var dest = destinationDir.appendingPathComponent(src.lastPathComponent)
            var idx = 1
            let stem = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension
            while fm.fileExists(atPath: dest.path) {
                let name = ext.isEmpty ? "\(stem)-\(idx)" : "\(stem)-\(idx).\(ext)"
                dest = destinationDir.appendingPathComponent(name)
                idx += 1
            }
            try fm.moveItem(at: src, to: dest)
            moved.append(dest)
        }
        return moved
    }
}

final class TerminalFileAction {
    static let shared = TerminalFileAction()

    func openTerminal(for urls: [URL], settings: AppSettings = .shared) throws {
        guard let first = urls.first(where: \.isFileURL) else {
            throw NSError(domain: "Daisy.Terminal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only local files and folders can open a terminal."])
        }
        var isDir: ObjCBool = false
        let folderURL: URL
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue {
            folderURL = first
        } else {
            folderURL = first.deletingLastPathComponent()
        }

        let bundleID = settings.terminalApplicationID
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")

        guard let resolvedAppURL = appURL else {
            throw NSError(domain: "Daisy.Terminal", code: 2, userInfo: [NSLocalizedDescriptionKey: "No supported Terminal application was found."])
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([folderURL], withApplicationAt: resolvedAppURL, configuration: config)
    }
}

final class AirDropSharingController: NSObject, NSSharingServiceDelegate {
    var onFinish: (() -> Void)?

    func share(_ urls: [URL]) throws {
        let local = urls.filter(\.isFileURL)
        guard !local.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: local)
        else {
            throw NSError(
                domain: "Daisy.AirDrop",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "AirDrop isn’t available for these files on this Mac."]
            )
        }
        service.delegate = self
        service.perform(withItems: local)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        onFinish?()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        onFinish?()
    }
}

// MARK: - Floating File Shelf Models (matching Tangerine's FloatingFileItem & FloatingFileGroupModel)

enum FloatingTabEdge: String, CaseIterable {
    case left
    case right
    case top
    case bottom
}

enum FloatingTabPresentation {
    case compact
    case expanded
}

enum FloatingTabViewMode {
    case icons
    case list
}

final class FloatingFileItem: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    let url: URL
    @Published var thumbnail: NSImage?

    static func == (lhs: FloatingFileItem, rhs: FloatingFileItem) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }

    init(url: URL) {
        self.url = url
        self.thumbnail = NSWorkspace.shared.icon(forFile: url.path)
        loadQuickLookThumbnail()
    }

    private func loadQuickLookThumbnail() {
        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 128, height: 128),
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async {
                self?.thumbnail = img
            }
        }
    }
}

// MARK: - Drag Source Card View (allows dragging files out of the Float shelf + right-click context menu)

final class FloatingFileCardView: NSView, NSDraggingSource {
    let item: FloatingFileItem
    var allActionItems: () -> [FloatingFileItem]
    var onOpen: ((FloatingFileItem) -> Void)?
    var onRemove: ((FloatingFileItem) -> Void)?
    var onConvert: (([URL], ConversionFanMode) -> Void)?

    private let imageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    private var mouseDownPoint: NSPoint?
    private var cancellable: AnyCancellable?

    init(
        item: FloatingFileItem,
        viewMode: FloatingTabViewMode,
        allActionItems: @escaping () -> [FloatingFileItem]
    ) {
        self.item = item
        self.allActionItems = allActionItems
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = item.thumbnail
        addSubview(imageView)

        nameLabel.stringValue = item.url.lastPathComponent
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)

        let bytes = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        sizeLabel.stringValue = bytes > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            : "Folder"
        sizeLabel.font = .systemFont(ofSize: 9.5)
        sizeLabel.textColor = .secondaryLabelColor
        addSubview(sizeLabel)

        if let xImg = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove from Float") {
            removeButton.image = xImg
        }
        removeButton.bezelStyle = .inline
        removeButton.isBordered = false
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        removeButton.toolTip = "Remove from Float"
        addSubview(removeButton)

        cancellable = item.$thumbnail.receive(on: DispatchQueue.main).sink { [weak self] img in
            self?.imageView.image = img
        }
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func layout() {
        super.layout()
        if bounds.height >= 72 {
            // Grid icon card layout
            imageView.frame = NSRect(x: (bounds.width - 42) * 0.5, y: bounds.height - 50, width: 42, height: 42)
            nameLabel.alignment = .center
            nameLabel.frame = NSRect(x: 4, y: 16, width: bounds.width - 8, height: 15)
            sizeLabel.alignment = .center
            sizeLabel.frame = NSRect(x: 4, y: 3, width: bounds.width - 8, height: 13)
            removeButton.frame = NSRect(x: bounds.width - 19, y: bounds.height - 19, width: 16, height: 16)
        } else {
            // Compact list row layout
            imageView.frame = NSRect(x: 8, y: (bounds.height - 28) * 0.5, width: 28, height: 28)
            nameLabel.alignment = .left
            nameLabel.frame = NSRect(x: 42, y: bounds.midY - 1, width: bounds.width - 68, height: 15)
            sizeLabel.alignment = .left
            sizeLabel.frame = NSRect(x: 42, y: bounds.midY - 14, width: bounds.width - 68, height: 12)
            removeButton.frame = NSRect(x: bounds.width - 24, y: (bounds.height - 16) * 0.5, width: 16, height: 16)
        }
    }

    @objc private func removeClicked() {
        onRemove?(item)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onOpen?(item)
            return
        }
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let pt = convert(event.locationInWindow, from: nil)
        guard hypot(pt.x - start.x, pt.y - start.y) >= 4 else { return }
        mouseDownPoint = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let icon = item.thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path)
        draggingItem.setDraggingFrame(NSRect(x: pt.x - 24, y: pt.y - 24, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .every
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open", action: #selector(ctxOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let revealItem = NSMenuItem(title: "Show in Finder", action: #selector(ctxReveal), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let convItem = NSMenuItem(title: "Convert with Wheel…", action: #selector(ctxConvert), keyEquivalent: "")
        convItem.target = self
        menu.addItem(convItem)

        let toolsItem = NSMenuItem(title: "Open in Tools Wheel…", action: #selector(ctxTools), keyEquivalent: "")
        toolsItem.target = self
        menu.addItem(toolsItem)

        menu.addItem(.separator())

        let copyItem = NSMenuItem(title: "Copy File", action: #selector(ctxCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let removeItem = NSMenuItem(title: "Remove from Float", action: #selector(removeClicked), keyEquivalent: "")
        removeItem.target = self
        menu.addItem(removeItem)
        return menu
    }

    @objc private func ctxOpen() { onOpen?(item) }
    @objc private func ctxReveal() { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    @objc private func ctxConvert() { onConvert?([item.url], .conversions) }
    @objc private func ctxTools() { onConvert?([item.url], .fileTools) }
    @objc private func ctxCopy() { try? FileClipboardController.shared.copyFiles([item.url]) }
}

// MARK: - Floating File Window Controller (matching Tangerine's FloatingFileWindowController at 0x100220f84)

final class FloatingFileWindowController: NSWindowController, NSWindowDelegate {
    var onDismiss: ((FloatingFileWindowController) -> Void)?
    var onOpenWheel: (([URL], ConversionFanMode) -> Void)?

    private(set) var items: [FloatingFileItem] = []
    private var presentation: FloatingTabPresentation = .expanded
    private var viewMode: FloatingTabViewMode = .icons
    private var attachedEdge: FloatingTabEdge?

    private let rootGlass = FluidDropGlassView()
    private let headerView = NSView()
    private let paperclipButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "Float")
    private let viewModeButton = NSButton()
    private let convertAllButton = NSButton()
    private let collapseButton = NSButton()
    private let closeButton = NSButton()
    private let scrollView = NSScrollView()
    private let cardsContainer = FlippedDocumentView()
    private let compactBadgeButton = NSButton()

    init(urls: [URL]) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 256, height: 268),
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
        panel.delegate = self

        setupUI(in: panel)
        addFiles(urls)
        positionInitialWindow()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func addFiles(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            if !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                items.append(FloatingFileItem(url: url))
            }
        }
        rebuildCards()
    }

    private func positionInitialWindow() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = max(visible.minX + 16, min(mouse.x - window.frame.width * 0.5, visible.maxX - window.frame.width - 16))
        let y = max(visible.minY + 16, min(mouse.y - window.frame.height * 0.5, visible.maxY - window.frame.height - 16))
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func setupUI(in panel: NSPanel) {
        rootGlass.frame = NSRect(x: 0, y: 0, width: 256, height: 268)
        rootGlass.autoresizingMask = [.width, .height]
        rootGlass.material = .hudWindow
        rootGlass.blendingMode = .behindWindow
        rootGlass.state = .active
        rootGlass.wantsLayer = true
        rootGlass.layer?.cornerRadius = 18
        rootGlass.layer?.cornerCurve = .continuous
        rootGlass.layer?.masksToBounds = true
        rootGlass.layer?.borderWidth = 1
        rootGlass.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        rootGlass.onFilesDropped = { [weak self] urls in
            self?.addFiles(urls)
            if self?.presentation == .compact {
                self?.setPresentation(.expanded)
            }
        }
        panel.contentView = rootGlass

        // Header bar
        headerView.frame = NSRect(x: 0, y: 230, width: 256, height: 38)
        headerView.autoresizingMask = [.width, .minYMargin]
        rootGlass.addSubview(headerView)

        if let clipImg = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Float") {
            paperclipButton.image = clipImg
        }
        paperclipButton.bezelStyle = .inline
        paperclipButton.isBordered = false
        paperclipButton.contentTintColor = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1.0)
        paperclipButton.frame = NSRect(x: 12, y: 9, width: 20, height: 20)
        paperclipButton.target = self
        paperclipButton.action = #selector(togglePresentation)
        headerView.addSubview(paperclipButton)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 34, y: 10, width: 108, height: 17)
        headerView.addSubview(titleLabel)

        if let convImg = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle", accessibilityDescription: "Convert All") {
            convertAllButton.image = convImg
        }
        convertAllButton.bezelStyle = .inline
        convertAllButton.isBordered = false
        convertAllButton.contentTintColor = .secondaryLabelColor
        convertAllButton.toolTip = "Open Conversion Wheel for all floated files"
        convertAllButton.target = self
        convertAllButton.action = #selector(convertAllClicked)
        convertAllButton.frame = NSRect(x: 158, y: 9, width: 22, height: 20)
        headerView.addSubview(convertAllButton)

        if let gridImg = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Toggle View Mode") {
            viewModeButton.image = gridImg
        }
        viewModeButton.bezelStyle = .inline
        viewModeButton.isBordered = false
        viewModeButton.contentTintColor = .secondaryLabelColor
        viewModeButton.toolTip = "Switch between Icons and List view"
        viewModeButton.target = self
        viewModeButton.action = #selector(toggleViewModeClicked)
        viewModeButton.frame = NSRect(x: 182, y: 9, width: 22, height: 20)
        headerView.addSubview(viewModeButton)

        if let minImg = NSImage(systemSymbolName: "chevron.compact.right", accessibilityDescription: "Collapse to Edge Tab") {
            collapseButton.image = minImg
        }
        collapseButton.bezelStyle = .inline
        collapseButton.isBordered = false
        collapseButton.contentTintColor = .secondaryLabelColor
        collapseButton.toolTip = "Collapse Float into compact Paperclip tab"
        collapseButton.target = self
        collapseButton.action = #selector(togglePresentation)
        collapseButton.frame = NSRect(x: 206, y: 9, width: 20, height: 20)
        headerView.addSubview(collapseButton)

        if let xImg = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close Float") {
            closeButton.image = xImg
        }
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close Float without deleting files"
        closeButton.target = self
        closeButton.action = #selector(closeFloatClicked)
        closeButton.frame = NSRect(x: 228, y: 9, width: 20, height: 20)
        headerView.addSubview(closeButton)

        // Scrollable cards area
        scrollView.frame = NSRect(x: 10, y: 10, width: 236, height: 218)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = cardsContainer
        rootGlass.addSubview(scrollView)

        // Compact paperclip button (shown when collapsed to screen edge)
        compactBadgeButton.bezelStyle = .inline
        compactBadgeButton.isBordered = false
        compactBadgeButton.font = .systemFont(ofSize: 12, weight: .bold)
        compactBadgeButton.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Expand Float")
        compactBadgeButton.imagePosition = .imageLeading
        compactBadgeButton.contentTintColor = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1.0)
        compactBadgeButton.target = self
        compactBadgeButton.action = #selector(togglePresentation)
        compactBadgeButton.isHidden = true
        rootGlass.addSubview(compactBadgeButton)
    }

    private func rebuildCards() {
        cardsContainer.subviews.forEach { $0.removeFromSuperview() }
        titleLabel.stringValue = items.count == 1 ? "1 Floated File" : "\(items.count) Floated Files"
        compactBadgeButton.title = " \(items.count)"

        let containerW: CGFloat = 236
        if viewMode == .icons {
            let cols = 2
            let gap: CGFloat = 8
            let cardW = (containerW - gap) / CGFloat(cols)
            let cardH: CGFloat = 86
            let rows = max(1, (items.count + cols - 1) / cols)
            let totalH = max(218, CGFloat(rows) * (cardH + gap))
            cardsContainer.frame = NSRect(x: 0, y: 0, width: containerW, height: totalH)

            for (idx, item) in items.enumerated() {
                let col = idx % cols
                let row = idx / cols
                let card = makeCard(for: item)
                card.frame = NSRect(
                    x: CGFloat(col) * (cardW + gap),
                    y: CGFloat(row) * (cardH + gap),
                    width: cardW,
                    height: cardH
                )
                cardsContainer.addSubview(card)
            }
        } else {
            let rowH: CGFloat = 42
            let gap: CGFloat = 6
            let totalH = max(218, CGFloat(items.count) * (rowH + gap))
            cardsContainer.frame = NSRect(x: 0, y: 0, width: containerW, height: totalH)

            for (idx, item) in items.enumerated() {
                let card = makeCard(for: item)
                card.frame = NSRect(
                    x: 0,
                    y: CGFloat(idx) * (rowH + gap),
                    width: containerW,
                    height: rowH
                )
                cardsContainer.addSubview(card)
            }
        }
    }

    private func makeCard(for item: FloatingFileItem) -> FloatingFileCardView {
        let card = FloatingFileCardView(item: item, viewMode: viewMode) { [weak self] in
            self?.items ?? []
        }
        card.onOpen = { item in
            NSWorkspace.shared.open(item.url)
        }
        card.onRemove = { [weak self] item in
            guard let self else { return }
            self.items.removeAll { $0.id == item.id }
            if self.items.isEmpty {
                self.closeFloatClicked()
            } else {
                self.rebuildCards()
            }
        }
        card.onConvert = { [weak self] urls, mode in
            self?.onOpenWheel?(urls, mode)
        }
        return card
    }

    func windowDidMove(_ notification: Notification) {
        guard presentation == .expanded, let window else { return }
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let f = window.frame
        if abs(f.minX - visible.minX) < 18 {
            attachedEdge = .left
        } else if abs(f.maxX - visible.maxX) < 18 {
            attachedEdge = .right
        } else {
            attachedEdge = nil
        }
    }

    @objc private func togglePresentation() {
        setPresentation(presentation == .expanded ? .compact : .expanded)
    }

    private func setPresentation(_ next: FloatingTabPresentation) {
        guard presentation != next, let window else { return }
        presentation = next
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if next == .compact {
            headerView.isHidden = true
            scrollView.isHidden = true
            compactBadgeButton.isHidden = false
            let compactSize = NSSize(width: 68, height: 42)
            compactBadgeButton.frame = NSRect(origin: .zero, size: compactSize)
            let stickRight = (window.frame.midX >= visible.midX)
            let newX = stickRight ? (visible.maxX - compactSize.width - 4) : (visible.minX + 4)
            let newFrame = NSRect(x: newX, y: window.frame.midY - compactSize.height * 0.5, width: compactSize.width, height: compactSize.height)
            window.setFrame(newFrame, display: true, animate: true)
        } else {
            let expandedSize = NSSize(width: 256, height: 268)
            var newX = window.frame.origin.x
            if newX + expandedSize.width > visible.maxX - 8 {
                newX = visible.maxX - expandedSize.width - 12
            }
            newX = max(visible.minX + 12, newX)
            let newY = max(visible.minY + 12, min(window.frame.midY - expandedSize.height * 0.5, visible.maxY - expandedSize.height - 12))
            let newFrame = NSRect(x: newX, y: newY, width: expandedSize.width, height: expandedSize.height)
            window.setFrame(newFrame, display: true, animate: true)
            headerView.isHidden = false
            scrollView.isHidden = false
            compactBadgeButton.isHidden = true
            rebuildCards()
        }
    }

    @objc private func toggleViewModeClicked() {
        viewMode = (viewMode == .icons) ? .list : .icons
        let sym = (viewMode == .icons) ? "list.bullet" : "square.grid.2x2"
        viewModeButton.image = NSImage(systemSymbolName: sym, accessibilityDescription: "Toggle View Mode")
        rebuildCards()
    }

    @objc private func convertAllClicked() {
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }
        onOpenWheel?(urls, .conversions)
    }

    @objc private func closeFloatClicked() {
        window?.close()
        onDismiss?(self)
    }
}

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class FluidDropGlassView: NSVisualEffectView {
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }
}
