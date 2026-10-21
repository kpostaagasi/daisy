// Daisy — radial conversion/tools/actions fan view inspired by Tangerine's ConversionOverlayView & FormatDropTarget.
import AppKit
import QuartzCore

// MARK: - Highlight Sound & Haptics Player (matching Tangerine's FanHighlightSoundPlayer)

final class FanHighlightSoundPlayer {
    static let shared = FanHighlightSoundPlayer()
    private var lastPlayUptime: TimeInterval = 0

    func playHighlightFeedback() {
        guard AppSettings.shared.soundsAndHapticsEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayUptime >= 0.035 else { return }
        lastPlayUptime = now

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        if let sound = NSSound(named: NSSound.Name("Tink")) ?? NSSound(named: NSSound.Name("Pop")) {
            sound.volume = 0.22
            sound.play()
        }
    }
}

// MARK: - Petal Tint View (matching Tangerine's PetalTintView)

final class PetalTintView: NSView {
    var accentColor: NSColor = NSColor(srgbRed: 1.0, green: 0.32, blue: 0.0, alpha: 1.0) {
        didSet { needsDisplay = true }
    }
    var isHighlighted: Bool = false {
        didSet { needsDisplay = true }
    }
    var theme: ConversionFanTheme = .glass {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let topColor: NSColor
        let bottomColor: NSColor

        if isHighlighted {
            topColor = accentColor.blended(withFraction: 0.18, of: .white)?.withAlphaComponent(0.92)
                ?? accentColor.withAlphaComponent(0.92)
            bottomColor = accentColor.blended(withFraction: 0.15, of: .black)?.withAlphaComponent(0.86)
                ?? accentColor.withAlphaComponent(0.86)
        } else {
            switch theme {
            case .glass:
                if isDark {
                    topColor = accentColor.blended(withFraction: 0.72, of: .white)?.withAlphaComponent(0.16)
                        ?? NSColor.white.withAlphaComponent(0.14)
                    bottomColor = NSColor.white.withAlphaComponent(0.06)
                } else {
                    topColor = NSColor.white.withAlphaComponent(0.68)
                    bottomColor = accentColor.blended(withFraction: 0.82, of: .white)?.withAlphaComponent(0.45)
                        ?? NSColor.white.withAlphaComponent(0.45)
                }
            case .metallic:
                if isDark {
                    topColor = NSColor(calibratedWhite: 0.30, alpha: 0.92)
                    bottomColor = NSColor(calibratedWhite: 0.14, alpha: 0.95)
                } else {
                    topColor = NSColor(calibratedWhite: 0.96, alpha: 0.94)
                    bottomColor = NSColor(calibratedWhite: 0.80, alpha: 0.94)
                }
            }
        }

        let cgColors = [topColor.cgColor, bottomColor.cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: cgColors, locations: locations)
        else { return }

        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.maxY),
            end: CGPoint(x: bounds.midX, y: bounds.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}

// MARK: - Wedge Sector Petal View (matching Tangerine's FormatDropTarget at 0x10005ad08)

final class FormatDropTarget: NSView {
    let action: ConversionFanAction
    let slotIndex: Int
    let petalCenterAngle: CGFloat
    let sectorAngle: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let labelInnerRadius: CGFloat = 40.0
    private static let labelMinFontSize: CGFloat = 8.5
    private static let labelMaxWidth: CGFloat = 82
    private static let labelOuterMargin: CGFloat = 16
    private static let labelRadiusStep: CGFloat = 3
    private static let labelTextInset: CGFloat = 8
    private static let labelClearance: CGFloat = 1.5
    private static let iconSide: CGFloat = 16
    private static let iconGap: CGFloat = 2

    var onActivate: ((ConversionFanAction) -> Void)?

    var isHighlighted: Bool = false {
        didSet {
            guard oldValue != isHighlighted else { return }
            updateAppearance(animated: true)
        }
    }

    var theme: ConversionFanTheme = AppSettings.shared.conversionFanTheme {
        didSet {
            tintView.theme = theme
            updateAppearance(animated: false)
        }
    }

    private let glassView = NSVisualEffectView()
    private let glassMask = CAShapeLayer()
    private let tintView = PetalTintView()
    private let contentContainer = NSView()
    private let contentMask = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let formatLabel = NSTextField(labelWithString: "")
    private let actionIconView = NSImageView()
    private var selectionPath: CGPath?

    init(
        action: ConversionFanAction,
        slotIndex: Int,
        centerAngle: CGFloat,
        sectorAngle: CGFloat,
        innerRadius: CGFloat = 56.0,
        outerRadius: CGFloat = 156.0,
        frame: NSRect
    ) {
        self.action = action
        self.slotIndex = slotIndex
        self.petalCenterAngle = centerAngle
        self.sectorAngle = sectorAngle
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        super.init(frame: frame)

        wantsLayer = true
        layer?.masksToBounds = false

        glassView.frame = bounds
        glassView.autoresizingMask = [.width, .height]
        glassView.material = .hudWindow
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.mask = glassMask
        addSubview(glassView)

        contentContainer.frame = bounds
        contentContainer.autoresizingMask = [.width, .height]
        contentContainer.wantsLayer = true
        contentContainer.layer?.mask = contentMask
        addSubview(contentContainer)

        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        tintView.accentColor = action.accentColor
        tintView.theme = theme
        contentContainer.addSubview(tintView)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1.25
        borderLayer.lineJoin = .round
        contentContainer.layer?.addSublayer(borderLayer)

        formatLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        formatLabel.alignment = .center
        formatLabel.lineBreakMode = .byWordWrapping
        formatLabel.usesSingleLineMode = false
        formatLabel.maximumNumberOfLines = 2
        formatLabel.cell?.wraps = true
        formatLabel.cell?.truncatesLastVisibleLine = true
        formatLabel.stringValue = action.label
        contentContainer.addSubview(formatLabel)

        if let sym = action.symbolName,
           let img = NSImage(systemSymbolName: sym, accessibilityDescription: action.label) {
            actionIconView.image = img
            actionIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
            actionIconView.imageScaling = .scaleProportionallyUpOrDown
            contentContainer.addSubview(actionIconView)
        } else {
            actionIconView.isHidden = true
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(action.detailTitle)

        rebuildGeometry()
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    // Let parent ConversionOverlayView handle hit-testing and polar routing
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance(animated: false)
    }

    override func layout() {
        super.layout()
        rebuildGeometry()
    }

    func containsPolarPoint(_ point: CGPoint) -> Bool {
        guard let path = selectionPath else { return false }
        return path.contains(point)
    }

    private func rebuildGeometry() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = Self.makeRoundedSectorPath(
            center: center,
            centerAngle: petalCenterAngle,
            sectorAngle: sectorAngle,
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            gapWidth: 4.5,
            cornerRadius: 10.0
        )
        selectionPath = path

        glassMask.frame = bounds
        glassMask.path = path
        glassMask.fillColor = NSColor.black.cgColor

        contentMask.frame = bounds
        contentMask.path = path
        contentMask.fillColor = NSColor.black.cgColor

        borderLayer.frame = bounds
        borderLayer.path = path

        // Icon (above) and text (below) stacked and centred on the label radius; symbol petals sit further out
        let hasSymbol = action.symbolName != nil
        let baseRadius = hasSymbol
            ? innerRadius + (outerRadius - innerRadius) * 0.62
            : labelInnerRadius + (outerRadius - innerRadius) * 0.68
        let placement = placeLabel(hasSymbol: hasSymbol, baseRadius: baseRadius, center: center)
        let frames = labelFrames(
            anchor: placement.anchor,
            font: placement.font,
            lines: placement.lines,
            width: placement.width,
            hasSymbol: hasSymbol
        )

        formatLabel.font = placement.font
        formatLabel.maximumNumberOfLines = placement.lines
        formatLabel.frame = frames.text
        actionIconView.isHidden = frames.icon == nil
        if let icon = frames.icon {
            actionIconView.frame = icon
        }
    }

    private struct LabelPlacement {
        let anchor: CGPoint
        let font: NSFont
        let lines: Int
        let width: CGFloat
    }

    /// Chooses font, line count and width for the label at the smallest radius (from `baseRadius` outward) where it fits inside the petal.
    /// Order: single line shrinking from the base size down to 8.5pt, then two lines at 8.5pt. Truncates only when neither fits.
    private func placeLabel(hasSymbol: Bool, baseRadius: CGFloat, center: CGPoint) -> LabelPlacement {
        let weight: NSFont.Weight = hasSymbol ? .semibold : .bold
        let baseSize: CGFloat = hasSymbol ? 10.5 : 12.0
        let maxRadius = outerRadius - Self.labelOuterMargin
        let radii = Array(stride(from: baseRadius, through: maxRadius, by: Self.labelRadiusStep))
        func anchor(_ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(petalCenterAngle) * radius, y: center.y + sin(petalCenterAngle) * radius)
        }

        for size in stride(from: baseSize, through: Self.labelMinFontSize, by: -0.5) {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            let needed = Self.textWidth(action.label, font: font) + Self.labelTextInset
            for radius in radii {
                let point = anchor(radius)
                if needed <= maxLabelWidth(at: point, font: font, lines: 1, hasSymbol: hasSymbol) {
                    return LabelPlacement(anchor: point, font: font, lines: 1, width: needed)
                }
            }
        }

        let wrapFont = NSFont.systemFont(ofSize: Self.labelMinFontSize, weight: weight)
        for radius in radii {
            let point = anchor(radius)
            let width = maxLabelWidth(at: point, font: wrapFont, lines: 2, hasSymbol: hasSymbol)
            if wrapFits(width: width, font: wrapFont) {
                return LabelPlacement(anchor: point, font: wrapFont, lines: 2, width: width)
            }
        }

        // Neither fits at any radius: wrap at the outermost radius; the last line truncates.
        let point = anchor(maxRadius)
        let width = maxLabelWidth(at: point, font: wrapFont, lines: 2, hasSymbol: hasSymbol)
        return LabelPlacement(anchor: point, font: wrapFont, lines: 2, width: width)
    }

    /// Text box and icon frames for `lines` of text (icon above, when present), stacked and centred vertically on `anchor`.
    private func labelFrames(anchor: CGPoint, font: NSFont, lines: Int, width: CGFloat, hasSymbol: Bool) -> (text: CGRect, icon: CGRect?) {
        let textHeight = CGFloat(lines) * Self.lineHeight(font)
        let stackHeight = textHeight + (hasSymbol ? Self.iconSide + Self.iconGap : 0)
        let text = CGRect(x: anchor.x - width / 2, y: anchor.y - stackHeight / 2, width: width, height: textHeight)
        guard hasSymbol else { return (text, nil) }
        let icon = CGRect(x: anchor.x - Self.iconSide / 2, y: text.maxY + Self.iconGap, width: Self.iconSide, height: Self.iconSide)
        return (text, icon)
    }

    /// Widest label box (at most `labelMaxWidth`) centred on `point` whose text and icon stay inside the petal.
    private func maxLabelWidth(at point: CGPoint, font: NSFont, lines: Int, hasSymbol: Bool) -> CGFloat {
        let probe = labelFrames(anchor: point, font: font, lines: lines, width: 0, hasSymbol: hasSymbol)
        if let icon = probe.icon, !petalContains(icon) { return 0 }
        func fits(_ width: CGFloat) -> Bool {
            petalContains(labelFrames(anchor: point, font: font, lines: lines, width: width, hasSymbol: hasSymbol).text)
        }
        if fits(Self.labelMaxWidth) { return Self.labelMaxWidth }
        var low: CGFloat = 0
        var high = Self.labelMaxWidth
        while high - low > 0.5 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        return low
    }

    /// True when the label wraps into two lines within `width` and no single word overflows it.
    private func wrapFits(width: CGFloat, font: NSFont) -> Bool {
        let usable = width - Self.labelTextInset
        guard usable > 0 else { return false }
        let longestWord = action.label
            .split(separator: " ")
            .map { Self.textWidth(String($0), font: font) }
            .max() ?? 0
        guard longestWord <= usable else { return false }
        let attributed = NSAttributedString(string: action.label, attributes: [.font: font])
        let rect = attributed.boundingRect(
            with: CGSize(width: usable, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return rect.height <= 2 * Self.lineHeight(font) + 1
    }

    /// True when `rect`, grown by the clearance, lies inside the petal. Probes corners and edge midpoints.
    private func petalContains(_ rect: CGRect) -> Bool {
        guard let path = selectionPath else { return false }
        let r = rect.insetBy(dx: -Self.labelClearance, dy: -Self.labelClearance)
        let probes = [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
            CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
        ]
        return probes.allSatisfy { path.contains($0) }
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    private func updateAppearance(animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.14 : 0.0)

        tintView.isHighlighted = isHighlighted
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isHighlighted {
            formatLabel.textColor = .white
            actionIconView.contentTintColor = .white
            borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.65).cgColor
            borderLayer.lineWidth = 1.8
        } else {
            let fg: NSColor = isDark
                ? NSColor.white.withAlphaComponent(0.92)
                : NSColor.black.withAlphaComponent(0.85)
            formatLabel.textColor = fg
            actionIconView.contentTintColor = action.accentColor
            borderLayer.strokeColor = (isDark
                ? NSColor.white.withAlphaComponent(0.20)
                : NSColor.black.withAlphaComponent(0.14)).cgColor
            borderLayer.lineWidth = 1.15
        }

        CATransaction.commit()
    }

    func playIntroAnimation(delay: CFTimeInterval) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let collapsedPath = Self.makeRoundedSectorPath(
            center: center,
            centerAngle: petalCenterAngle,
            sectorAngle: sectorAngle,
            innerRadius: innerRadius * 0.72,
            outerRadius: innerRadius + 18,
            gapWidth: 3.0,
            cornerRadius: 6.0
        )
        guard let targetPath = selectionPath else { return }

        let timing = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        for maskLayer in [glassMask, contentMask, borderLayer] {
            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = collapsedPath
            anim.toValue = targetPath
            anim.duration = 0.24
            anim.beginTime = CACurrentMediaTime() + delay
            anim.timingFunction = timing
            anim.fillMode = .backwards
            maskLayer.add(anim, forKey: "tangerine.transition.path")
        }
    }

    /// Builds an annular sector path with angular gap and rounded corners (matching Tangerine's NativePetalGlassShape).
    static func makeRoundedSectorPath(
        center: CGPoint,
        centerAngle: CGFloat,
        sectorAngle: CGFloat,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        gapWidth: CGFloat,
        cornerRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        guard outerRadius > innerRadius, sectorAngle > 0.05 else { return path }

        let halfGapInner = min(sectorAngle * 0.22, asin(min(0.95, (gapWidth * 0.5) / max(1, innerRadius))))
        let halfGapOuter = min(sectorAngle * 0.22, asin(min(0.95, (gapWidth * 0.5) / max(1, outerRadius))))

        let startInner = centerAngle - sectorAngle * 0.5 + halfGapInner
        let endInner = centerAngle + sectorAngle * 0.5 - halfGapInner
        let startOuter = centerAngle - sectorAngle * 0.5 + halfGapOuter
        let endOuter = centerAngle + sectorAngle * 0.5 - halfGapOuter

        guard endInner > startInner, endOuter > startOuter else { return path }

        let cr = min(cornerRadius, (outerRadius - innerRadius) * 0.28)
        let innerCornerAngle = min((endInner - startInner) * 0.25, cr / max(1, innerRadius))
        let outerCornerAngle = min((endOuter - startOuter) * 0.25, cr / max(1, outerRadius))

        let rIn = innerRadius + cr * 0.65
        let rOut = outerRadius - cr * 0.65

        let pInStart = CGPoint(
            x: center.x + cos(startInner) * rIn,
            y: center.y + sin(startInner) * rIn
        )
        let pOutStart = CGPoint(
            x: center.x + cos(startOuter) * rOut,
            y: center.y + sin(startOuter) * rOut
        )
        let cOutStart = CGPoint(
            x: center.x + cos(startOuter) * outerRadius,
            y: center.y + sin(startOuter) * outerRadius
        )
        let pOutArcStart = CGPoint(
            x: center.x + cos(startOuter + outerCornerAngle) * outerRadius,
            y: center.y + sin(startOuter + outerCornerAngle) * outerRadius
        )
        let cOutEnd = CGPoint(
            x: center.x + cos(endOuter) * outerRadius,
            y: center.y + sin(endOuter) * outerRadius
        )
        let pOutEnd = CGPoint(
            x: center.x + cos(endOuter) * rOut,
            y: center.y + sin(endOuter) * rOut
        )
        let pInEnd = CGPoint(
            x: center.x + cos(endInner) * rIn,
            y: center.y + sin(endInner) * rIn
        )
        let cInEnd = CGPoint(
            x: center.x + cos(endInner) * innerRadius,
            y: center.y + sin(endInner) * innerRadius
        )
        let pInArcEnd = CGPoint(
            x: center.x + cos(endInner - innerCornerAngle) * innerRadius,
            y: center.y + sin(endInner - innerCornerAngle) * innerRadius
        )
        let cInStart = CGPoint(
            x: center.x + cos(startInner) * innerRadius,
            y: center.y + sin(startInner) * innerRadius
        )

        path.move(to: pInStart)
        path.addLine(to: pOutStart)
        path.addQuadCurve(to: pOutArcStart, control: cOutStart)
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startOuter + outerCornerAngle,
            endAngle: endOuter - outerCornerAngle,
            clockwise: false
        )
        path.addQuadCurve(to: pOutEnd, control: cOutEnd)
        path.addLine(to: pInEnd)
        path.addQuadCurve(to: pInArcEnd, control: cInEnd)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endInner - innerCornerAngle,
            endAngle: startInner + innerCornerAngle,
            clockwise: true
        )
        path.addQuadCurve(to: pInStart, control: cInStart)
        path.closeSubpath()
        return path
    }
}

// MARK: - Fan Center Label View (matching Tangerine's FanCenterLabelView at 0x100057f7c)

final class FanCenterLabelView: NSView {
    private let backgroundView = NSVisualEffectView()
    private let solidBackgroundView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        backgroundView.identifier = NSUserInterfaceItemIdentifier("fan.centerLabel.background")
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)

        solidBackgroundView.identifier = NSUserInterfaceItemIdentifier("fan.centerLabel.solidBackground")
        solidBackgroundView.wantsLayer = true
        solidBackgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        solidBackgroundView.layer?.borderWidth = 1.0
        solidBackgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        addSubview(solidBackgroundView)

        titleLabel.identifier = NSUserInterfaceItemIdentifier("fan.centerLabel.text")
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 2
        titleLabel.usesSingleLineMode = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        solidBackgroundView.frame = bounds
        let r = min(bounds.width, bounds.height) * 0.5
        backgroundView.layer?.cornerRadius = r
        solidBackgroundView.layer?.cornerRadius = r

        if subtitleLabel.stringValue.isEmpty {
            titleLabel.frame = NSRect(x: 8, y: bounds.midY - 10, width: bounds.width - 16, height: 20)
            subtitleLabel.isHidden = true
        } else {
            subtitleLabel.isHidden = false
            titleLabel.frame = NSRect(x: 8, y: bounds.midY - 2, width: bounds.width - 16, height: 18)
            subtitleLabel.frame = NSRect(x: 8, y: bounds.midY - 17, width: bounds.width - 16, height: 14)
        }
    }

    func update(title: String, subtitle: String = "", accent: NSColor? = nil) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        if let accent {
            solidBackgroundView.layer?.borderColor = accent.withAlphaComponent(0.65).cgColor
        } else {
            solidBackgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        }
        needsLayout = true
    }
}

// MARK: - Conversion Overlay View (matching Tangerine's ConversionOverlayView at 0x10005e1cc)

final class FanPanelView: NSView {
    static let defaultSize = NSSize(width: 372, height: 372)

    var onActionSelected: (([URL], ConversionFanAction) -> Void)?
    var onDismissRequested: (() -> Void)?
    var onFileSelectionRequested: ((ConversionFanAction) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?

    private(set) var fanMode: ConversionFanMode = .conversions
    private(set) var sourceURLs: [URL] = []
    private(set) var targets: [FormatDropTarget] = []
    private var highlightedTarget: FormatDropTarget?

    private let outerRadius: CGFloat = 156.0
    private let innerRadius: CGFloat = 56.0
    private let targetHostView = NSView()
    private let centerLabel = FanCenterLabelView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
    private let modeSwitchContainer = NSVisualEffectView()
    private var modeButtons: [NSButton] = []
    private let statusMaterial = NSVisualEffectView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var themeObserver: NSObjectProtocol?

    init(onActionSelected: @escaping ([URL], ConversionFanAction) -> Void) {
        self.onActionSelected = onActionSelected
        super.init(frame: NSRect(origin: .zero, size: Self.defaultSize))

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        targetHostView.frame = bounds
        targetHostView.autoresizingMask = [.width, .height]
        targetHostView.wantsLayer = true
        addSubview(targetHostView)

        addSubview(centerLabel)

        // Bottom mode switcher pill (Convert ⌥ | Tools ⌘ | Actions ⌃)
        modeSwitchContainer.material = .hudWindow
        modeSwitchContainer.blendingMode = .behindWindow
        modeSwitchContainer.state = .active
        modeSwitchContainer.wantsLayer = true
        modeSwitchContainer.layer?.cornerRadius = 13
        modeSwitchContainer.layer?.masksToBounds = true
        modeSwitchContainer.layer?.borderWidth = 1
        modeSwitchContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        addSubview(modeSwitchContainer)

        for mode in ConversionFanMode.allCases {
            let btn = NSButton(title: mode.shortTitle, target: self, action: #selector(modeButtonClicked(_:)))
            btn.tag = mode.rawValue
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = .systemFont(ofSize: 10.5, weight: .semibold)
            modeSwitchContainer.addSubview(btn)
            modeButtons.append(btn)
        }

        // Top status pill
        statusMaterial.material = .hudWindow
        statusMaterial.blendingMode = .behindWindow
        statusMaterial.state = .active
        statusMaterial.wantsLayer = true
        statusMaterial.layer?.cornerRadius = 11
        statusMaterial.layer?.masksToBounds = true
        statusMaterial.isHidden = true
        addSubview(statusMaterial)

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.alignment = .center
        statusMaterial.addSubview(statusLabel)

        registerForDraggedTypes([.fileURL])

        themeObserver = NotificationCenter.default.addObserver(
            forName: .daisyFanThemeDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let theme = AppSettings.shared.conversionFanTheme
            self.targets.forEach { $0.theme = theme }
        }

        configure(urls: [], mode: .conversions, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func layout() {
        super.layout()
        targetHostView.frame = bounds
        let hubDiameter: CGFloat = 96
        centerLabel.frame = NSRect(
            x: bounds.midX - hubDiameter * 0.5,
            y: bounds.midY - hubDiameter * 0.5,
            width: hubDiameter,
            height: hubDiameter
        )

        let pillWidth: CGFloat = 228
        let pillHeight: CGFloat = 26
        modeSwitchContainer.frame = NSRect(
            x: bounds.midX - pillWidth * 0.5,
            y: 4,
            width: pillWidth,
            height: pillHeight
        )
        let btnW = pillWidth / CGFloat(max(1, modeButtons.count))
        for (idx, btn) in modeButtons.enumerated() {
            btn.frame = NSRect(x: CGFloat(idx) * btnW, y: 0, width: btnW, height: pillHeight)
        }

        statusMaterial.frame = NSRect(x: bounds.midX - 130, y: bounds.height - 26, width: 260, height: 22)
        statusLabel.frame = NSRect(x: 8, y: 3, width: 244, height: 16)
    }

    func configure(urls: [URL], mode: ConversionFanMode, animated: Bool = true) {
        if !urls.isEmpty {
            self.sourceURLs = urls
        }
        self.fanMode = mode
        rebuildPetals(animated: animated)
        updateModeButtons()
        updateCenterLabel()
    }

    private func updateModeButtons() {
        for btn in modeButtons {
            let mode = ConversionFanMode(rawValue: btn.tag) ?? .conversions
            let modSym = AppSettings.shared.modifierSymbolForMode(mode)
            btn.title = "\(mode.shortTitle) \(modSym)"
            btn.contentTintColor = (mode == fanMode)
                ? NSColor(srgbRed: 1.0, green: 0.38, blue: 0.08, alpha: 1.0)
                : .secondaryLabelColor
        }
    }

    @objc private func modeButtonClicked(_ sender: NSButton) {
        guard let mode = ConversionFanMode(rawValue: sender.tag) else { return }
        FanHighlightSoundPlayer.shared.playHighlightFeedback()
        configure(urls: sourceURLs, mode: mode, animated: true)
    }

    private func rebuildPetals(animated: Bool) {
        targets.forEach { $0.removeFromSuperview() }
        targets.removeAll()
        highlightedTarget = nil

        let actions = ConversionFanAction.validActions(for: sourceURLs, mode: fanMode)
        guard !actions.isEmpty else {
            setStatus("No tools available for selected files")
            return
        }
        setStatus("")

        let count = actions.count
        let sectorAngle = (2.0 * .pi) / CGFloat(max(count, 3))
        let theme = AppSettings.shared.conversionFanTheme

        for (index, action) in actions.enumerated() {
            // Start at top (π/2) and step clockwise like Tangerine
            let angle = (.pi / 2.0) - CGFloat(index) * sectorAngle
            let petal = FormatDropTarget(
                action: action,
                slotIndex: index,
                centerAngle: angle,
                sectorAngle: sectorAngle,
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                frame: targetHostView.bounds
            )
            petal.autoresizingMask = [.width, .height]
            petal.theme = theme
            targetHostView.addSubview(petal)
            targets.append(petal)

            if animated {
                petal.playIntroAnimation(delay: Double(index) * 0.012)
            }
        }
    }

    private func updateCenterLabel() {
        if let hovered = highlightedTarget {
            let srcBadge = sourceSummaryBadge()
            centerLabel.update(
                title: hovered.action.label,
                subtitle: srcBadge.isEmpty ? hovered.action.detailTitle : "\(srcBadge) → \(hovered.action.label)",
                accent: hovered.action.accentColor
            )
            return
        }

        let badge = sourceSummaryBadge()
        if !badge.isEmpty {
            centerLabel.update(
                title: badge,
                subtitle: fanMode.title,
                accent: nil
            )
        } else {
            centerLabel.update(
                title: fanMode.shortTitle,
                subtitle: "Drop or Click",
                accent: nil
            )
        }
    }

    private func sourceSummaryBadge() -> String {
        guard !sourceURLs.isEmpty else { return "" }
        if sourceURLs.count == 1, let first = sourceURLs.first {
            if let fmt = ConversionFormat.detect(for: first) {
                return fmt.title
            }
            let ext = first.pathExtension.uppercased()
            return ext.isEmpty ? "FOLDER" : ext
        }
        let formats = Set(sourceURLs.compactMap { ConversionFormat.detect(for: $0)?.title })
        if formats.count == 1, let only = formats.first {
            return "\(sourceURLs.count) \(only)"
        }
        return "\(sourceURLs.count) FILES"
    }

    func setStatus(_ text: String) {
        if text.isEmpty {
            statusMaterial.isHidden = true
            statusLabel.stringValue = ""
        } else {
            statusLabel.stringValue = text
            statusMaterial.isHidden = false
        }
    }

    func setBusy(_ busy: Bool) {
        alphaValue = busy ? 0.75 : 1.0
    }

    // MARK: - Polar Hit Testing

    private func petal(at viewPoint: NSPoint) -> FormatDropTarget? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = viewPoint.x - center.x
        let dy = viewPoint.y - center.y
        let r = hypot(dx, dy)
        guard r >= innerRadius - 4, r <= outerRadius + 10 else { return nil }
        for target in targets where target.containsPolarPoint(viewPoint) {
            return target
        }
        return nil
    }

    private func updateHighlightedTarget(at point: NSPoint) {
        let hit = petal(at: point)
        if hit !== highlightedTarget {
            highlightedTarget?.isHighlighted = false
            highlightedTarget = hit
            highlightedTarget?.isHighlighted = true
            if hit != nil {
                FanHighlightSoundPlayer.shared.playHighlightFeedback()
            }
            updateCenterLabel()
        }
    }

    // MARK: - Mouse Hover & Click Handling

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        updateHighlightedTarget(at: pt)
    }

    override func mouseExited(with event: NSEvent) {
        if highlightedTarget != nil {
            highlightedTarget?.isHighlighted = false
            highlightedTarget = nil
            updateCenterLabel()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        // Check if clicked inside center hub -> cycle mode, or outside outerRadius -> dismiss
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dist = hypot(pt.x - center.x, pt.y - center.y)

        if let hit = petal(at: pt) {
            FanHighlightSoundPlayer.shared.playHighlightFeedback()
            guard !sourceURLs.isEmpty else {
                onFileSelectionRequested?(hit.action)
                return
            }
            let files = sourceURLs
            sourceURLs = []
            onActionSelected?(files, hit.action)
        } else if dist < innerRadius {
            // Clicking the center hub cycles between Conversions -> Tools -> Actions
            let nextRaw = (fanMode.rawValue + 1) % ConversionFanMode.allCases.count
            if let nextMode = ConversionFanMode(rawValue: nextRaw) {
                FanHighlightSoundPlayer.shared.playHighlightFeedback()
                configure(urls: sourceURLs, mode: nextMode, animated: true)
            }
        } else if dist > outerRadius + 12 && !modeSwitchContainer.frame.contains(pt) {
            onDismissRequested?()
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragStateChanged?(true)
        let files = extractDraggedURLs(from: sender)
        if !files.isEmpty && files != sourceURLs {
            configure(urls: files, mode: fanMode, animated: false)
        }
        let pt = convert(sender.draggingLocation, from: nil)
        updateHighlightedTarget(at: pt)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pt = convert(sender.draggingLocation, from: nil)
        updateHighlightedTarget(at: pt)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragStateChanged?(false)
        if highlightedTarget != nil {
            highlightedTarget?.isHighlighted = false
            highlightedTarget = nil
            updateCenterLabel()
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragStateChanged?(false)
        let files = extractDraggedURLs(from: sender)
        let activeFiles = files.isEmpty ? sourceURLs : files
        let pt = convert(sender.draggingLocation, from: nil)

        if let hit = petal(at: pt) {
            highlightedTarget?.isHighlighted = false
            highlightedTarget = nil
            sourceURLs = []
            onActionSelected?(activeFiles, hit.action)
            return !activeFiles.isEmpty
        }

        // Dropped on the center hub -> stage the files and keep the wheel open so user can click any petal/mode!
        if !activeFiles.isEmpty {
            sourceURLs = activeFiles
            rebuildPetals(animated: true)
            updateCenterLabel()
            return true
        }
        return false
    }

    private func extractDraggedURLs(from sender: NSDraggingInfo) -> [URL] {
        let pb = sender.draggingPasteboard
        return pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []
    }
}
