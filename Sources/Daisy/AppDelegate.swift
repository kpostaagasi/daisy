// Daisy — application lifecycle and controller orchestration inspired by Tangerine's AppDelegate.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    let store = ConversionTaskStore()
    private(set) lazy var engine = ConversionEngine(settings: settings)

    private var menuBar: MenuBarController!
    private var overlayPanel: FloatingDropPanel!
    private var dragGestureMonitor: DragGestureMonitor!
    private var settingsWindow: SettingsWindowController!
    private var welcomeWindow: WelcomeWindowController!

    private var floatingFileControllers: [FloatingFileWindowController] = []
    private var fileToolOptionsControllers: [FileToolOptionsWindowController] = []
    private var qrCodeResultsControllers: [QRCodeResultsWindowController] = []
    private var progressControllers: [OperationProgressWindowController] = []
    private var airDropControllers: [AirDropSharingController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Monitoring drag-to-convert gestures")

        overlayPanel = FloatingDropPanel { [weak self] files, action in
            self?.handleFanAction(files: files, action: action)
        }

        dragGestureMonitor = DragGestureMonitor(settings: settings)
        dragGestureMonitor.isOverlayVisible = { [weak self] in
            self?.overlayPanel.isVisible ?? false
        }
        dragGestureMonitor.isDragInsideOverlay = { [weak self] in
            guard let panel = self?.overlayPanel else { return false }
            return panel.isDragInside || panel.containsMouseLocation
        }
        dragGestureMonitor.onTriggerWheel = { [weak self] urls, mode in
            self?.overlayPanel.show(urls: urls, mode: mode, atMouseLocation: true)
        }
        dragGestureMonitor.onDismissOverlay = { [weak self] in
            self?.overlayPanel.dismiss()
        }
        dragGestureMonitor.start()

        menuBar = MenuBarController(store: store)
        menuBar.onOpenWheel = { [weak self] urls, mode, atMouse in
            self?.overlayPanel.show(urls: urls, mode: mode, atMouseLocation: atMouse)
        }
        menuBar.onCreateFloat = { [weak self] in
            self?.promptAndCreateFloat()
        }
        menuBar.install()

        settingsWindow = SettingsWindowController(settings: settings)
        welcomeWindow = WelcomeWindowController()
        welcomeWindow.onTryWheel = { [weak self] mode in
            self?.overlayPanel.show(urls: [], mode: mode, atMouseLocation: false)
        }

        NotificationCenter.default.addObserver(
            forName: .daisyOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            self?.settingsWindow.show()
        }

        NotificationCenter.default.addObserver(
            forName: .daisyOpenWelcome, object: nil, queue: .main
        ) { [weak self] _ in
            self?.welcomeWindow.show()
        }

        // Show the radial fan in the top-right corner on launch or show Welcome on first run
        if !settings.hasCompletedWelcome {
            welcomeWindow.show()
        }
        overlayPanel.show(urls: [], mode: .conversions, atMouseLocation: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragGestureMonitor?.stop()
        ProcessInfo.processInfo.enableAutomaticTermination("Monitoring drag-to-convert gestures")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            overlayPanel.show(urls: [], mode: .conversions, atMouseLocation: false)
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Action Dispatch (matching Tangerine's AppDelegate at 0x100030fd0..0x100039200)

    private func handleFanAction(files: [URL], action: ConversionFanAction) {
        guard !files.isEmpty else { return }

        switch action {
        case .convert(let format):
            runConversion(files: files, format: format)

        case .fileTool(let tool):
            if tool == .readQRCode {
                openQRCodeScanner(for: files)
            } else if tool.requiresOptionsWindow {
                openToolOptionsWindow(for: files, tool: tool)
            } else {
                runFileTool(files: files, tool: tool, options: FileToolOptions())
            }

        case .float:
            floatFiles(files)

        case .airDrop:
            shareViaAirDrop(files)

        case .copy:
            do {
                try FileClipboardController.shared.copyFiles(files)
                store.lastResult = "Copied \(files.count) file(s)"
                store.succeeded = true
            } catch {
                presentErrorAlert(title: "Couldn’t copy files", message: error.localizedDescription)
            }

        case .copyPath:
            do {
                try FileClipboardController.shared.copyPaths(files)
                store.lastResult = "Copied \(files.count) path(s)"
                store.succeeded = true
            } catch {
                presentErrorAlert(title: "Couldn’t copy file paths", message: error.localizedDescription)
            }

        case .move:
            do {
                let moved = try FileMoveAction.shared.moveFilesInteractively(files)
                if !moved.isEmpty {
                    store.lastResult = "Moved \(moved.count) item(s)"
                    store.succeeded = true
                    NSWorkspace.shared.activateFileViewerSelecting(moved)
                }
            } catch {
                presentErrorAlert(title: "Couldn’t move files", message: error.localizedDescription)
            }

        case .openTerminal:
            do {
                try TerminalFileAction.shared.openTerminal(for: files, settings: settings)
                store.lastResult = "Opened Terminal"
                store.succeeded = true
            } catch {
                presentErrorAlert(title: "Couldn’t open terminal", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Conversions & Tools Execution with Progress HUD

    private func runConversion(files: [URL], format: ConversionFormat) {
        let sourceTitle = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        let taskID = store.beginTask(sourceName: sourceTitle, targetTitle: format.title)
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Daisy conversion")

        let progressWC = OperationProgressWindowController()
        progressControllers.append(progressWC)
        progressWC.onClose = { [weak self, weak progressWC] in
            guard let self, let progressWC else { return }
            self.progressControllers.removeAll { $0 === progressWC }
        }
        progressWC.showNearCursor()
        progressWC.updateProgress(
            title: "Converting to \(format.title)…",
            status: sourceTitle,
            fraction: nil
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let outcome = self.engine.convert(files: files, format: format) { index, total, name in
                DispatchQueue.main.async {
                    let frac = total > 1 ? Double(index - 1) / Double(total) : nil
                    progressWC.updateProgress(
                        title: "Converting to \(format.title) (\(index)/\(total))",
                        status: name,
                        fraction: frac
                    )
                }
            }
            DispatchQueue.main.async {
                ProcessInfo.processInfo.endActivity(activity)
                switch outcome {
                case .success(let urls):
                    let names = urls.map(\.lastPathComponent).prefix(3).joined(separator: " · ")
                    self.store.endTask(taskID, result: "Created: \(names)", succeeded: true)
                    progressWC.window?.close()
                    self.progressControllers.removeAll { $0 === progressWC }
                    NSWorkspace.shared.activateFileViewerSelecting(urls)

                case .failure(let message):
                    self.store.endTask(taskID, result: "Conversion failed", succeeded: false)
                    progressWC.showFailure(title: "Conversion failed!", details: message)
                }
            }
        }
    }

    private func runFileTool(files: [URL], tool: FileTool, options: FileToolOptions) {
        let sourceTitle = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        let taskID = store.beginTask(sourceName: sourceTitle, targetTitle: tool.title)
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Daisy file tool")

        let progressWC = OperationProgressWindowController()
        progressControllers.append(progressWC)
        progressWC.onClose = { [weak self, weak progressWC] in
            guard let self, let progressWC else { return }
            self.progressControllers.removeAll { $0 === progressWC }
        }
        progressWC.showNearCursor()
        progressWC.updateProgress(
            title: "\(tool.fullTitle)…",
            status: sourceTitle,
            fraction: nil
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let outcome = self.engine.runTool(files: files, tool: tool, options: options) { index, total, name in
                DispatchQueue.main.async {
                    let frac = total > 1 ? Double(index - 1) / Double(total) : nil
                    progressWC.updateProgress(
                        title: "\(tool.fullTitle) (\(index)/\(total))",
                        status: name,
                        fraction: frac
                    )
                }
            }
            DispatchQueue.main.async {
                ProcessInfo.processInfo.endActivity(activity)
                switch outcome {
                case .success(let urls):
                    let names = urls.map(\.lastPathComponent).prefix(3).joined(separator: " · ")
                    self.store.endTask(taskID, result: "\(tool.title): \(names)", succeeded: true)
                    progressWC.window?.close()
                    self.progressControllers.removeAll { $0 === progressWC }
                    NSWorkspace.shared.activateFileViewerSelecting(urls)

                case .failure(let message):
                    self.store.endTask(taskID, result: "\(tool.title) failed", succeeded: false)
                    progressWC.showFailure(title: "Operation failed!", details: message)
                }
            }
        }
    }

    // MARK: - Window Controllers Management

    private func openToolOptionsWindow(for files: [URL], tool: FileTool) {
        let wc = FileToolOptionsWindowController(urls: files, tool: tool) { [weak self] urls, tool, opts in
            self?.runFileTool(files: urls, tool: tool, options: opts)
        }
        fileToolOptionsControllers.append(wc)
        wc.show()
    }

    private func openQRCodeScanner(for files: [URL]) {
        let wc = QRCodeResultsWindowController(urls: files)
        qrCodeResultsControllers.append(wc)
        wc.show()
    }

    func floatFiles(_ files: [URL]) {
        if settings.floatWheelBehavior == .addToExisting,
           let existing = floatingFileControllers.last,
           existing.window?.isVisible == true {
            existing.addFiles(files)
            existing.window?.orderFrontRegardless()
            return
        }

        let wc = FloatingFileWindowController(urls: files)
        wc.onDismiss = { [weak self] controller in
            self?.floatingFileControllers.removeAll { $0 === controller }
        }
        wc.onOpenWheel = { [weak self] urls, mode in
            self?.overlayPanel.show(urls: urls, mode: mode, atMouseLocation: true)
        }
        floatingFileControllers.append(wc)
        wc.window?.orderFrontRegardless()
    }

    private func promptAndCreateFloat() {
        let panel = NSOpenPanel()
        panel.title = "Choose files or folders to Float"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        floatFiles(panel.urls)
    }

    private func shareViaAirDrop(_ files: [URL]) {
        let controller = AirDropSharingController()
        airDropControllers.append(controller)
        controller.onFinish = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.airDropControllers.removeAll { $0 === controller }
        }
        do {
            try controller.share(files)
        } catch {
            airDropControllers.removeAll { $0 === controller }
            presentErrorAlert(title: "Couldn’t AirDrop files", message: error.localizedDescription)
        }
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
