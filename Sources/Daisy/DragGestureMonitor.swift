// Daisy — global drag gesture and modifier shortcut monitor inspired by Tangerine's DragGestureMonitor.
import AppKit
import CoreGraphics
import Foundation

final class DragGestureMonitor {
    private let settings: AppSettings
    private let dragPasteboard = NSPasteboard(name: .drag)

    var isOverlayVisible: (() -> Bool)?
    var isDragInsideOverlay: (() -> Bool)?
    var onTriggerWheel: (([URL], ConversionFanMode) -> Void)?
    var onDismissOverlay: (() -> Void)?

    private let triggerGraceInterval: TimeInterval = 0.35
    private let idlePollingInterval: TimeInterval = 0.10
    private let activePollingInterval: TimeInterval = 1.0 / 60.0
    private let dragStartDistance: CGFloat = 4

    private var timer: DispatchSourceTimer?
    private var isPollingActively = false

    private var wasPrimaryButtonDown = false
    private var wasEscapeDown = false
    private var previousModifiers: NSEvent.ModifierFlags = []

    private var mouseDownLocation: NSPoint = .zero
    private var pasteboardChangeCountBeforeMouseDown: Int = 0
    private var activeDragPasteboardChangeCount: Int?
    private var lastValidTriggerUptime: TimeInterval = 0

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.pasteboardChangeCountBeforeMouseDown = dragPasteboard.changeCount
    }

    func start() {
        stop()
        previousModifiers = NSEvent.modifierFlags.intersection([.control, .option, .shift, .command])
        scheduleTimer(active: false)
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func scheduleTimer(active: Bool) {
        isPollingActively = active
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        let interval = active ? activePollingInterval : idlePollingInterval
        let leeway: DispatchTimeInterval = active ? .milliseconds(2) : .milliseconds(20)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        source.setEventHandler { [weak self] in
            self?.poll()
        }
        source.resume()
        timer = source
    }

    private func poll() {
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        let nsFlags = NSEvent.modifierFlags
        let rawMods = (UInt(cgFlags.rawValue) | nsFlags.rawValue) & 0x1e0000
        let modifiers = NSEvent.ModifierFlags(rawValue: rawMods)

        let isLeftDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
            || ((NSEvent.pressedMouseButtons & 1) != 0)
        let isEscapeDown = CGEventSource.keyState(.combinedSessionState, key: 0x35)

        let currentChangeCount = dragPasteboard.changeCount
        let overlayVisible = isOverlayVisible?() ?? false

        let pointer = NSEvent.mouseLocation

        // A drag starts only after the pointer travels past the threshold and the drag pasteboard changes during this press
        let hadActiveDrag = activeDragPasteboardChangeCount != nil
        if isLeftDown {
            if !wasPrimaryButtonDown {
                mouseDownLocation = pointer
                pasteboardChangeCountBeforeMouseDown = currentChangeCount
                activeDragPasteboardChangeCount = nil
            }
            let distance = hypot(pointer.x - mouseDownLocation.x, pointer.y - mouseDownLocation.y)
            if distance >= dragStartDistance, currentChangeCount != pasteboardChangeCountBeforeMouseDown {
                activeDragPasteboardChangeCount = currentChangeCount
            }
        } else {
            activeDragPasteboardChangeCount = nil
        }

        // Escape key dismisses the overlay immediately
        if isEscapeDown && !wasEscapeDown && overlayVisible {
            onDismissOverlay?()
            wasEscapeDown = isEscapeDown
            previousModifiers = modifiers
            wasPrimaryButtonDown = isLeftDown
            updatePollingSpeed(isLeftDown: isLeftDown)
            return
        }

        // Detect newly pressed modifier key(s)
        let newlyPressedRaw = modifiers.rawValue & ~previousModifiers.rawValue
        let matchedMode: ConversionFanMode? = (newlyPressedRaw != 0) ? settings.matchingMode(for: modifiers) : nil

        if isLeftDown, activeDragPasteboardChangeCount != nil, let mode = matchedMode {
            let draggedURLs = readDraggedFileURLs()
            if !draggedURLs.isEmpty {
                lastValidTriggerUptime = ProcessInfo.processInfo.systemUptime
                onTriggerWheel?(draggedURLs, mode)
            } else if overlayVisible {
                // Allow switching wheel modes while overlay is already open
                lastValidTriggerUptime = ProcessInfo.processInfo.systemUptime
                onTriggerWheel?([], mode)
            }
        } else if !isLeftDown, wasPrimaryButtonDown, overlayVisible {
            // If drag was released outside the overlay after the grace window, dismiss
            let inside = isDragInsideOverlay?() ?? false
            let elapsed = ProcessInfo.processInfo.systemUptime - lastValidTriggerUptime
            if !inside && elapsed > triggerGraceInterval && hadActiveDrag {
                onDismissOverlay?()
            }
        }

        wasEscapeDown = isEscapeDown
        previousModifiers = modifiers
        wasPrimaryButtonDown = isLeftDown
        updatePollingSpeed(isLeftDown: isLeftDown)
    }

    private func updatePollingSpeed(isLeftDown: Bool) {
        let shouldPollActively = isLeftDown || (isOverlayVisible?() ?? false)
        if shouldPollActively != isPollingActively {
            scheduleTimer(active: shouldPollActively)
        }
    }

    func readDraggedFileURLs() -> [URL] {
        // Check if drag pasteboard has file URLs
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = dragPasteboard.readObjects(forClasses: classes, options: options) as? [URL], !urls.isEmpty {
            return urls
        }
        return []
    }
}
