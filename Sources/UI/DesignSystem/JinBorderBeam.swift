import SwiftUI
import AppKit
import QuartzCore

/// Decorative traveling / breathing hairline on the composer card.
///
/// Motion is expressed as Core Animation transforms/opacity. No display link
/// and no full-composer redraw are needed while the beam is running.
struct JinBorderBeam: View {
    enum Style: Equatable {
        case line
        case pulseInner
    }

    var isActive: Bool
    var style: Style
    var cornerRadius: CGFloat
    var strength: Double = 0.45

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        JinBorderBeamRepresentable(
            isActive: isActive,
            style: style,
            cornerRadius: cornerRadius,
            strength: strength,
            reduceMotion: reduceMotion,
            isDark: colorScheme == .dark
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct JinBorderBeamRepresentable: NSViewRepresentable {
    var isActive: Bool
    var style: JinBorderBeam.Style
    var cornerRadius: CGFloat
    var strength: Double
    var reduceMotion: Bool
    var isDark: Bool

    func makeNSView(context: Context) -> JinBorderBeamNSView {
        let view = JinBorderBeamNSView()
        view.apply(
            isActive: isActive,
            style: style,
            cornerRadius: cornerRadius,
            strength: strength,
            reduceMotion: reduceMotion,
            isDark: isDark
        )
        return view
    }

    func updateNSView(_ nsView: JinBorderBeamNSView, context: Context) {
        nsView.apply(
            isActive: isActive,
            style: style,
            cornerRadius: cornerRadius,
            strength: strength,
            reduceMotion: reduceMotion,
            isDark: isDark
        )
    }
}

final class JinBorderBeamNSView: NSView {
    private let lineClipLayer = CALayer()
    private let lineGradientLayer = CAGradientLayer()
    private let pulseLayer = CAShapeLayer()

    private var isActive = false
    private var style: JinBorderBeam.Style = .line
    private var cornerRadius: CGFloat = JinRadius.large
    private var strength: Double = 0.45
    private var reduceMotion = false
    private var isDark = true
    private var lastGeometry = CGRect.null

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor

        lineClipLayer.backgroundColor = NSColor.clear.cgColor
        lineClipLayer.masksToBounds = true
        lineClipLayer.isGeometryFlipped = true
        lineClipLayer.isHidden = true

        lineGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        lineGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        lineGradientLayer.locations = [0, 0.5, 1]
        lineClipLayer.addSublayer(lineGradientLayer)

        pulseLayer.fillColor = NSColor.clear.cgColor
        pulseLayer.lineWidth = 1
        pulseLayer.isHidden = true

        layer?.addSublayer(lineClipLayer)
        layer?.addSublayer(pulseLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }

    func apply(
        isActive: Bool,
        style: JinBorderBeam.Style,
        cornerRadius: CGFloat,
        strength: Double,
        reduceMotion: Bool,
        isDark: Bool
    ) {
        let unchanged = self.isActive == isActive
            && self.style == style
            && self.cornerRadius == cornerRadius
            && self.strength == strength
            && self.reduceMotion == reduceMotion
            && self.isDark == isDark
        guard !unchanged else { return }

        self.isActive = isActive
        self.style = style
        self.cornerRadius = cornerRadius
        self.strength = strength
        self.reduceMotion = reduceMotion
        self.isDark = isDark
        updateAppearance()
        updateMotion()
    }

    override func layout() {
        super.layout()
        guard bounds != lastGeometry else { return }
        lastGeometry = bounds

        let highlightWidth = max(56, bounds.width * 0.22)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineClipLayer.frame = bounds
        lineClipLayer.cornerRadius = cornerRadius
        lineGradientLayer.bounds = CGRect(x: 0, y: 0, width: highlightWidth, height: 2)
        lineGradientLayer.position = CGPoint(x: -highlightWidth / 2, y: bounds.maxY - 1)
        pulseLayer.frame = bounds
        pulseLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        CATransaction.commit()

        updateMotion(restart: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMotion(restart: window != nil)
    }

    override func viewDidHide() {
        super.viewDidHide()
        removeMotion()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateMotion(restart: true)
    }

    private func updateAppearance() {
        let ink = isDark
            ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        lineGradientLayer.colors = [
            ink.copy(alpha: 0) ?? ink,
            ink.copy(alpha: 0.9 * strength) ?? ink,
            ink.copy(alpha: 0) ?? ink,
        ]
        pulseLayer.strokeColor = ink.copy(alpha: 0.58 * strength) ?? ink
        lineClipLayer.cornerRadius = cornerRadius
        if !bounds.isEmpty {
            pulseLayer.path = CGPath(
                roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        }
    }

    private func updateMotion(restart: Bool = false) {
        guard isActive, window != nil, !isHiddenOrHasHiddenAncestor else {
            lineClipLayer.isHidden = true
            pulseLayer.isHidden = true
            removeMotion()
            return
        }

        lineClipLayer.isHidden = style != .line
        pulseLayer.isHidden = style != .pulseInner

        if reduceMotion {
            removeMotion()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lineGradientLayer.position.x = bounds.midX
            CATransaction.commit()
            lineGradientLayer.opacity = style == .line ? 0.65 : 0
            pulseLayer.opacity = style == .pulseInner ? 0.65 : 0
            return
        }

        lineGradientLayer.opacity = 1
        pulseLayer.opacity = 1
        switch style {
        case .line:
            pulseLayer.removeAnimation(forKey: "jin.pulse")
            if restart || lineGradientLayer.animation(forKey: "jin.travel") == nil {
                addTravelAnimation()
            }
        case .pulseInner:
            lineGradientLayer.removeAnimation(forKey: "jin.travel")
            if restart || pulseLayer.animation(forKey: "jin.pulse") == nil {
                addPulseAnimation()
            }
        }
    }

    private func addTravelAnimation() {
        lineGradientLayer.removeAnimation(forKey: "jin.travel")
        let halfWidth = lineGradientLayer.bounds.width / 2
        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = -halfWidth
        travel.toValue = bounds.width + halfWidth
        travel.duration = 2.8
        travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .linear)
        travel.isRemovedOnCompletion = false
        lineGradientLayer.add(travel, forKey: "jin.travel")
    }

    private func addPulseAnimation() {
        pulseLayer.removeAnimation(forKey: "jin.pulse")
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0.35, 1, 0.35]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.duration = 2.3
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        pulseLayer.add(pulse, forKey: "jin.pulse")
    }

    private func removeMotion() {
        lineGradientLayer.removeAnimation(forKey: "jin.travel")
        pulseLayer.removeAnimation(forKey: "jin.pulse")
    }
}

extension View {
    func jinBorderBeam(
        isActive: Bool,
        style: JinBorderBeam.Style,
        cornerRadius: CGFloat,
        strength: Double = 0.45
    ) -> some View {
        overlay {
            JinBorderBeam(
                isActive: isActive,
                style: style,
                cornerRadius: cornerRadius,
                strength: strength
            )
        }
    }
}
