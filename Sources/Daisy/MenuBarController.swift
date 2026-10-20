// Daisy — the status bar menu: about the dropped files, settings, quit.
import AppKit

final class MenuBarController: NSObject {
    private let engine: ConversionEngine
    private let store: ConversionTaskStore
    private var statusItem: NSStatusItem?

    init(engine: ConversionEngine, store: ConversionTaskStore) {
        self.engine = engine
        self.store = store
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "camera.macro",
            accessibilityDescription: "Daisy"
        )
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Daisy — flower fresh file tools", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let stagedMenu = NSMenuItem(title: "Convert folder…", action: nil, keyEquivalent: "")
        stagedMenu.submenu = folderMenu()
        menu.addItem(stagedMenu)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let toolStatus = ToolLocator.toolStatus(AppSettings.shared)
        let statusline = NSMenuItem(
            title: toolStatus.allSatisfy(\.found)
                ? "Tools: ffmpeg ✓ cwebp ✓ exiftool ✓"
                : "Missing tools: " + toolStatus.filter { !$0.found }.map(\.name).joined(separator: " "),
                action: nil,
                keyEquivalent: ""
        )
        statusline.isEnabled = false
        menu.addItem(statusline)

        let installHint = NSMenuItem(
            title: "brew install ffmpeg webp exiftool",
            action: nil, keyEquivalent: ""
        )
        installHint.isEnabled = false
        menu.addItem(installHint)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Daisy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// Lets the user pick a folder of files, converts all of them to WebP.
    private func folderMenu() -> NSMenu {
        let submenu = NSMenu()
        for target in ConversionTarget.fan {
            let item = NSMenuItem(title: target.label, action: #selector(runFolderTarget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = target.label
            submenu.addItem(item)
        }
        return submenu
    }

    @objc func runFolderTarget(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        guard let target = ConversionTarget.fan.first(where: { $0.label == sender.representedObject as? String })
        else { return }

        store.isBusy = true
        let files = panel.urls
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.engine.convert(files: files, target: target)
            DispatchQueue.main.async {
                if case .success(let urls) = result {
                    self.store.lastResult = "Converted \(urls.count) file(s)"
                    self.store.succeeded = true
                } else if case .failure(let message) = result {
                    self.store.lastResult = message
                    self.store.succeeded = false
                }
                self.store.isBusy = false
            }
        }
    }

    @objc func openSettings() {
        NotificationCenter.default.post(name: .daisyOpenSettings, object: nil)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
