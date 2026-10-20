// Daisy — settings window: tool paths, output folder, timeout.
import AppKit

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let settings: AppSettings
    private var rows: [NSTextField] = []

    init(settings: AppSettings) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Daisy Settings"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 250))
        window?.contentView = content

        let rows: [(label: String, tag: Int)] = [
            ("ffmpeg path (empty = auto)", 0),
            ("cwebp path (empty = auto)", 1),
            ("exiftool path (empty = auto)", 2),
            ("Output folder (empty = alongside source)", 3),
        ]

        var y: CGFloat = 200
        for row in rows {
            let label = NSTextField(labelWithString: row.label)
            label.font = .systemFont(ofSize: 11)
            label.frame = NSRect(x: 20, y: y + 4, width: 440, height: 14)
            content.addSubview(label)

            let field = NSTextField(frame: NSRect(x: 20, y: y - 18, width: 440, height: 20))
            field.font = .systemFont(ofSize: 11)
            field.stringValue = valueForTag(row.tag)
            field.delegate = self
            field.target = self
            field.action = #selector(fieldChanged(_:))
            field.tag = row.tag
            content.addSubview(field)
            y -= 44
        }

        let timeoutLabel = NSTextField(labelWithString: "Conversion timeout (seconds)")
        timeoutLabel.font = .systemFont(ofSize: 11)
        timeoutLabel.frame = NSRect(x: 20, y: 68, width: 300, height: 14)
        content.addSubview(timeoutLabel)

        let timeout = NSTextField(frame: NSRect(x: 20, y: 44, width: 120, height: 20))
        timeout.font = .systemFont(ofSize: 11)
        timeout.stringValue = String(settings.timeoutSeconds)
        timeout.tag = 4
        timeout.delegate = self
        timeout.target = self
        timeout.action = #selector(fieldChanged(_:))
        content.addSubview(timeout)

        let note = NSTextField(labelWithString:
            "Daisy is fully unlocked — no paywall. GPL tools are not bundled; "
            + "install them with Homebrew: brew install ffmpeg webp exiftool"
        )
        note.font = .systemFont(ofSize: 10)
        note.textColor = .secondaryLabelColor
        note.isSelectable = false
        note.isBezeled = false
        note.drawsBackground = false
        note.frame = NSRect(x: 20, y: 8, width: 440, height: 30)
        note.usesSingleLineMode = false
        content.addSubview(note)
    }

    private func valueForTag(_ tag: Int) -> String {
        switch tag {
        case 0: return settings.ffmpegPath
        case 1: return settings.cwebpPath
        case 2: return settings.exiftoolPath
        default: return settings.outputDirectory
        }
    }

    private func setValue(_ value: String, forTag tag: Int) {
        switch tag {
        case 0: settings.ffmpegPath = value
        case 1: settings.cwebpPath = value
        case 2: settings.exiftoolPath = value
        case 3: settings.outputDirectory = value
        default: break
        }
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        if sender.tag == 4, let seconds = Int(sender.stringValue) {
            settings.timeoutSeconds = seconds
            return
        }
        setValue(sender.stringValue, forTag: sender.tag)
    }
}
