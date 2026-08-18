import AppKit
import QuartzCore

/// AppKit-owned orb whose steady-state motion runs entirely in Core Animation.
///
/// The procedural engine is sampled once per visual mode. Core Animation then
/// interpolates stable dot layers at the display refresh rate, so streaming
/// markdown/layout work never triggers per-frame model generation or drawing.
final class JinActivityOrbNSView: NSView {
    private let dotContainerLayer = CALayer()

    private var kind: JinActivityKind = .working
    private var orbSize: JinActivityOrbSize = .inline
    private var paused = false
    private var pose: JinActivityOrbPose = .live
    private var isDark = true
    private var installedKey: InstalledKey?

    private struct InstalledKey: Equatable {
        let kind: JinActivityKind
        let size: JinActivityOrbSize
        let paused: Bool
        let pose: JinActivityOrbPose
        let isDark: Bool
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        dotContainerLayer.backgroundColor = NSColor.clear.cgColor
        dotContainerLayer.isGeometryFlipped = true
        layer?.addSublayer(dotContainerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let side = CGFloat(orbSize.value)
        return NSSize(width: side, height: side)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }

    func apply(
        kind: JinActivityKind,
        size: JinActivityOrbSize,
        paused: Bool,
        pose: JinActivityOrbPose = .live,
        isDark: Bool
    ) {
        let sizeChanged = orbSize != size
        let nextKey = InstalledKey(
            kind: kind,
            size: size,
            paused: paused,
            pose: pose,
            isDark: isDark
        )
        guard nextKey != installedKey else { return }

        self.kind = kind
        orbSize = size
        self.paused = paused
        self.pose = pose
        self.isDark = isDark

        if sizeChanged {
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
        installCurrentPose()
    }

    override func layout() {
        super.layout()
        let side = CGFloat(orbSize.value)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dotContainerLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        dotContainerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            clearDotLayers()
        } else {
            installedKey = nil
            installCurrentPose()
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        clearDotLayers()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        installedKey = nil
        installCurrentPose()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        installedKey = nil
        installCurrentPose()
    }

    private func installCurrentPose() {
        guard window != nil, !isHiddenOrHasHiddenAncestor else {
            clearDotLayers()
            return
        }

        let nextKey = InstalledKey(
            kind: kind,
            size: orbSize,
            paused: paused,
            pose: pose,
            isDark: isDark
        )
        guard nextKey != installedKey else { return }

        if paused || pose == .settled {
            installStaticFrame(staticFrame())
        } else {
            installAnimation(JinActivityOrbEngine.animationPlan(kind: kind, size: orbSize))
        }
        installedKey = nextKey
    }

    private func staticFrame() -> ActivityOrbFrame {
        if pose == .settled {
            return JinActivityOrbEngine.settledThoughtFrame(size: orbSize)
        }
        let preset = JinActivityOrbEngine.resolve(kind, size: orbSize)
        return JinActivityOrbEngine.frame(
            preset,
            size: orbSize.value,
            t: JinActivityOrbEngine.reducedMotionT * preset.speed
        )
    }

    private func installStaticFrame(_ frame: ActivityOrbFrame) {
        rebuildDotLayers(count: frame.dots.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (dotLayer, dot) in zip(dotContainerLayer.sublayers ?? [], frame.dots) {
            applyModel(dot, to: dotLayer)
        }
        CATransaction.commit()
    }

    private func installAnimation(_ plan: ActivityOrbAnimationPlan) {
        guard let firstFrame = plan.frames.first, plan.dotCount > 0 else {
            clearDotLayers()
            return
        }

        rebuildDotLayers(count: plan.dotCount)
        let keyTimes = plan.frames.indices.map {
            NSNumber(value: Double($0) / Double(max(1, plan.frames.count - 1)))
        }
        let beginTime = CACurrentMediaTime() + 0.02

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (dotIndex, dotLayer) in (dotContainerLayer.sublayers ?? []).enumerated() {
            let dots = plan.frames.map { $0.dots[dotIndex] }
            let firstDot = firstFrame.dots[dotIndex]
            applyModel(firstDot, to: dotLayer)
            dotLayer.backgroundColor = averageInk(for: dots)

            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = dots.map {
                NSValue(point: NSPoint(x: $0.x, y: $0.y))
            }
            position.keyTimes = keyTimes
            position.calculationMode = .linear
            position.duration = plan.duration

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = dots.map { NSNumber(value: $0.r) }
            scale.keyTimes = keyTimes
            scale.calculationMode = .linear
            scale.duration = plan.duration

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = dots.map { NSNumber(value: $0.a) }
            opacity.keyTimes = keyTimes
            opacity.calculationMode = .linear
            opacity.duration = plan.duration

            let group = CAAnimationGroup()
            group.animations = [position, scale, opacity]
            group.duration = plan.duration
            group.beginTime = beginTime
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            dotLayer.add(group, forKey: "jin.activity")
        }
        CATransaction.commit()
    }

    private func rebuildDotLayers(count: Int) {
        clearDotLayers()
        guard count > 0 else { return }

        for _ in 0..<count {
            let dotLayer = CALayer()
            dotLayer.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
            dotLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            dotLayer.cornerRadius = 1
            dotLayer.allowsEdgeAntialiasing = true
            dotContainerLayer.addSublayer(dotLayer)
        }
    }

    private func clearDotLayers() {
        dotContainerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        installedKey = nil
    }

    private func applyModel(_ dot: ActivityOrbDot, to layer: CALayer) {
        layer.position = CGPoint(x: dot.x, y: dot.y)
        layer.transform = CATransform3DMakeScale(dot.r, dot.r, 1)
        layer.opacity = Float(dot.a)
        layer.backgroundColor = ink(white: dot.white, alpha: 1)
    }

    private func averageInk(for dots: [ActivityOrbDot]) -> CGColor {
        guard !dots.isEmpty else { return ink(white: 0.5, alpha: 1) }
        let averageWhite = dots.reduce(0) { $0 + $1.white } / Double(dots.count)
        return ink(white: averageWhite, alpha: 1)
    }

    private func ink(white: Double, alpha: Double) -> CGColor {
        let clampedWhite = min(1, max(0, white))
        let gray = ((isDark ? 1 - clampedWhite : clampedWhite) * 255)
            .rounded(.toNearestOrAwayFromZero) / 255
        return CGColor(srgbRed: gray, green: gray, blue: gray, alpha: alpha)
    }
}
