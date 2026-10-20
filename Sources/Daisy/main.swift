// Daisy — main entry point and application lifecycle.
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Menu bar (LSUIElement) app
app.run()
