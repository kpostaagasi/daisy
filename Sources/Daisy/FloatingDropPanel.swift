// Daisy — the always-on-top floating drop panel with the conversion fan.
import AppKit
import Combine

final class FloatingDropPanel {
    private let engine: ConversionEngine
    private let store: ConversionTaskStore

    private var panel: NSPanel?
    private var fanView: FanPanelView?
    private var statusSubscriptions: Set<AnyCancellable> = []

    init(engine: ConversionEngine, store: ConversionTaskStore) {
        self.engine = engine
        self.store = store
    }

    func show() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 440, height: 440)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let fanView = FanPanelView { [weak self] files, target in
            self?.beginConversion(files: files, target: target)
        }
        panel.contentView = fanView

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 470, y: screen.maxY - 470))
        panel.orderFrontRegardless()

        self.panel = panel
        self.fanView = fanView

        store.$isBusy.receive(on: DispatchQueue.main)
            .sink { [weak fanView] busy in fanView?.setBusy(busy) }
            .store(in: &statusSubscriptions)
        store.$lastResult.receive(on: DispatchQueue.main)
            .sink { [weak fanView] text in fanView?.setStatus(text) }
            .store(in: &statusSubscriptions)
    }

    func beginConversion(files: [URL], target: ConversionTarget) {
        store.isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let outcome = self.engine.convert(files: files, target: target)
            DispatchQueue.main.async {
                switch outcome {
                case .success(let urls):
                    self.store.succeeded = true
                    let names = urls.map(\.lastPathComponent).prefix(3).joined(separator: " · ")
                    self.store.lastResult = urls.isEmpty ? "Nothing to convert" : "Converted: \(names)"
                case .failure(let message):
                    self.store.succeeded = false
                    self.store.lastResult = message
                }
                self.store.isBusy = false
            }
        }
    }
}
