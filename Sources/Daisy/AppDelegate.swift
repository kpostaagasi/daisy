// Daisy — application lifecycle, wires controllers together.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    private(set) lazy var engine = ConversionEngine(settings: settings)
    let store = ConversionTaskStore()

    private var menuBar: MenuBarController!
    private var panel: FloatingDropPanel!
    private var settingsWindow: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(engine: engine, store: store)
        menuBar.install()

        panel = FloatingDropPanel(engine: engine, store: store)
        panel.show()

        settingsWindow = SettingsWindowController(settings: settings)
        NotificationCenter.default.addObserver(
            forName: .daisyOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in self?.settingsWindow.show() }
    }

    func applicationSupportsSecureRestorableState() -> Bool { true }
}
