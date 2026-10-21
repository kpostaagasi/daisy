// Daisy — status bar menu controller inspired by Tangerine's MenuBarController.
import AppKit

final class StatusItemDropOverlayView: NSView {
    var onFilesDragged: (([URL]) -> Void)?
    var onMouseDown: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []
        if !urls.isEmpty {
            onFilesDragged?(urls)
        }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }

    override func rightMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private let store: ConversionTaskStore
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    var onOpenWheel: (([URL], ConversionFanMode, Bool) -> Void)?
    var onCreateFloat: (() -> Void)?

    init(store: ConversionTaskStore) {
        self.store = store
        super.init()
        self.store.onChange = { [weak self] in
            self?.updateStatusItemIcon()
        }
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Daisy"
            button.setAccessibilityLabel("Daisy")

            let dropOverlay = StatusItemDropOverlayView(frame: button.bounds)
            dropOverlay.autoresizingMask = [.width, .height]
            dropOverlay.onFilesDragged = { [weak self] urls in
                self?.onOpenWheel?(urls, .conversions, false)
            }
            dropOverlay.onMouseDown = { [weak item] in item?.button?.performClick(nil) }
            button.addSubview(dropOverlay)
        }

        statusItem = item
        updateStatusItemIcon()
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName = store.isBusy ? "arrow.triangle.2.circlepath.circle.fill" : "camera.macro"
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Daisy")
        img?.isTemplate = true
        button.image = img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Status row (matching Tangerine at 0x10029ed84: "Daisy is ready" / "Daisy is working")
        let statusTitle = store.isBusy ? "Daisy is working" : "Daisy is ready"
        let statusSymbol = store.isBusy ? "arrow.triangle.2.circlepath" : "checkmark.circle"
        let statusItemRow = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItemRow.isEnabled = false
        statusItemRow.image = NSImage(systemSymbolName: statusSymbol, accessibilityDescription: statusTitle)
        menu.addItem(statusItemRow)

        if !store.lastResult.isEmpty {
            let lastRow = NSMenuItem(title: store.lastResult, action: nil, keyEquivalent: "")
            lastRow.isEnabled = false
            lastRow.indentationLevel = 1
            menu.addItem(lastRow)
        }

        // 2. Active Tasks section (matching Tangerine at 0x10029f17c..0x10029fa60)
        if !store.activeTasks.isEmpty {
            menu.addItem(.separator())
            let activeHeader = NSMenuItem(title: "Active Tasks", action: nil, keyEquivalent: "")
            activeHeader.isEnabled = false
            menu.addItem(activeHeader)

            for task in store.activeTasks {
                let truncatedSource = task.sourceName.count > 38
                    ? String(task.sourceName.prefix(35)) + "…"
                    : task.sourceName
                let rowTitle = "\(truncatedSource)  →  \(task.targetTitle)"
                let row = NSMenuItem(title: rowTitle, action: nil, keyEquivalent: "")
                row.isEnabled = false
                row.indentationLevel = 1
                row.toolTip = "\(task.sourceName) → \(task.targetTitle)"
                row.image = NSImage(
                    systemSymbolName: "arrow.triangle.2.circlepath",
                    accessibilityDescription: "Active conversion"
                )
                menu.addItem(row)
            }
        }

        menu.addItem(.separator())

        // 3. Wheel & Float shelf launchers
        let settings = AppSettings.shared
        let convMod = DragModifierCombination(mask: settings.conversionDragModifierMask).symbolsString
        let toolsMod = DragModifierCombination(mask: settings.toolsDragModifierMask).symbolsString
        let actMod = DragModifierCombination(mask: settings.actionsDragModifierMask).symbolsString

        let convItem = NSMenuItem(
            title: "Conversion Wheel (\(convMod) While Dragging)",
            action: #selector(openConversionWheel),
            keyEquivalent: ""
        )
        convItem.target = self
        convItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(convItem)

        let toolsItem = NSMenuItem(
            title: "File Tools Wheel (\(toolsMod) While Dragging)",
            action: #selector(openToolsWheel),
            keyEquivalent: ""
        )
        toolsItem.target = self
        toolsItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
        menu.addItem(toolsItem)

        let actionsItem = NSMenuItem(
            title: "File Actions Wheel (\(actMod) While Dragging)",
            action: #selector(openActionsWheel),
            keyEquivalent: ""
        )
        actionsItem.target = self
        actionsItem.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        menu.addItem(actionsItem)

        let floatItem = NSMenuItem(
            title: "New Float Shelf…",
            action: #selector(createNewFloat),
            keyEquivalent: ""
        )
        floatItem.target = self
        floatItem.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)
        menu.addItem(floatItem)

        menu.addItem(.separator())

        // 4. Settings, Getting Started, About, Quit (matching Tangerine at 0x10029f2ac..0x10029f700)
        let settingsRow = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsRow.target = self
        settingsRow.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        menu.addItem(settingsRow)

        let welcomeRow = NSMenuItem(title: "Getting Started…", action: #selector(openWelcome), keyEquivalent: "")
        welcomeRow.target = self
        welcomeRow.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Getting Started")
        menu.addItem(welcomeRow)

        let aboutRow = NSMenuItem(title: "About Daisy", action: #selector(showAbout), keyEquivalent: "")
        aboutRow.target = self
        menu.addItem(aboutRow)

        menu.addItem(.separator())

        let quitRow = NSMenuItem(title: "Quit Daisy", action: #selector(quit), keyEquivalent: "q")
        quitRow.target = self
        menu.addItem(quitRow)
    }

    @objc private func openConversionWheel() {
        onOpenWheel?([], .conversions, false)
    }

    @objc private func openToolsWheel() {
        onOpenWheel?([], .fileTools, false)
    }

    @objc private func openActionsWheel() {
        onOpenWheel?([], .fileActions, false)
    }

    @objc private func createNewFloat() {
        onCreateFloat?()
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .daisyOpenSettings, object: nil)
    }

    @objc private func openWelcome() {
        NotificationCenter.default.post(name: .daisyOpenWelcome, object: nil)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
