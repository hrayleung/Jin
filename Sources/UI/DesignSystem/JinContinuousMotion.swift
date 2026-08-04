import SwiftUI

// MARK: - Continuous motion (time-based, uninterruptible)

/// Looping chrome motion that **cannot freeze mid-pose**.
///
/// State-driven `.repeatForever` animations (`@State isAnimating` + `offset` /
/// `scaleEffect`) are cancelled when an `NSHostingView` reconfigures, a parent
/// transaction disables animation, or a cell is recycled — leaving icons and
/// dots stuck halfway. These helpers read wall-clock time from
/// `TimelineView` every frame so the visual is always a pure function of
/// `Date` and never depends on an interruptible animation transaction.
///
/// Row-height-driving motion must still use fixed-duration easing in
/// `JinMotion` — continuous chrome here only uses transform/opacity.
enum JinContinuousMotion {
    /// Wave-dot bounce period (seconds for a full up-down cycle).
    static let wavePeriod: TimeInterval = 0.9

    /// Soft pulse period for thinking / running glyphs.
    static let pulsePeriod: TimeInterval = 1.2

    /// Terminal-rail running node pulse period.
    static let nodePulsePeriod: TimeInterval = 1.7

    /// Phase in `[0, 1)` from a stable clock.
    static func phase(at date: Date, period: TimeInterval, offset: TimeInterval = 0) -> Double {
        guard period > 0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate + offset
        let p = t.truncatingRemainder(dividingBy: period) / period
        return p < 0 ? p + 1 : p
    }

    /// Sinusoid in `[-1, 1]` from phase.
    static func sine(phase: Double) -> Double {
        sin(phase * 2 * Double.pi)
    }
}

// MARK: - Wave dots

/// Three bouncing dots used for “running / thinking” affordances.
struct JinWaveDots: View {
    var dotCount: Int = 3
    var dotSize: CGFloat = 4
    var spacing: CGFloat = 3
    var amplitude: CGFloat = 2.5
    var color: Color = .secondary
    /// Stagger as a fraction of the period between consecutive dots.
    var staggerFraction: Double = 0.17

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            staticDots
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                HStack(spacing: spacing) {
                    ForEach(0..<dotCount, id: \.self) { index in
                        Circle()
                            .fill(color)
                            .frame(width: dotSize, height: dotSize)
                            .offset(y: offsetY(at: context.date, index: index))
                    }
                }
            }
        }
    }

    private var staticDots: some View {
        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { _ in
                Circle()
                    .fill(color.opacity(0.7))
                    .frame(width: dotSize, height: dotSize)
            }
        }
    }

    private func offsetY(at date: Date, index: Int) -> CGFloat {
        let period = JinContinuousMotion.wavePeriod
        let offset = Double(index) * staggerFraction * period
        let phase = JinContinuousMotion.phase(at: date, period: period, offset: offset)
        return CGFloat(JinContinuousMotion.sine(phase: phase)) * -amplitude
    }
}

// MARK: - Soft scale/opacity pulse

/// Wraps content in a continuous soft pulse (scale + opacity). Time-based so
/// a hosting-view reconfigure never leaves content mid-scale.
struct JinPulseChrome<Content: View>: View {
    var period: TimeInterval = JinContinuousMotion.pulsePeriod
    var minScale: CGFloat = 1.0
    var maxScale: CGFloat = 1.1
    var minOpacity: Double = 0.65
    var maxOpacity: Double = 1.0
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content()
                .scaleEffect(1)
                .opacity(maxOpacity)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let phase = JinContinuousMotion.phase(at: context.date, period: period)
                // Map sine [-1,1] → [0,1]
                let t = (JinContinuousMotion.sine(phase: phase) + 1) * 0.5
                content()
                    .scaleEffect(minScale + (maxScale - minScale) * CGFloat(t))
                    .opacity(minOpacity + (maxOpacity - minOpacity) * t)
            }
        }
    }
}

// MARK: - Running node pulse (terminal rail)

/// Small filled circle whose scale/opacity pulses while a tool is running.
struct JinRunningNodePulse: View {
    var color: Color
    var baseSize: CGFloat = 6
    var minScale: CGFloat = 0.85
    var maxScale: CGFloat = 1.4
    var minOpacity: Double = 0.35
    var maxOpacity: Double = 1.0
    var period: TimeInterval = JinContinuousMotion.nodePulsePeriod

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Circle()
                .fill(color)
                .frame(width: baseSize, height: baseSize)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let phase = JinContinuousMotion.phase(at: context.date, period: period)
                let t = (JinContinuousMotion.sine(phase: phase) + 1) * 0.5
                Circle()
                    .fill(color)
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(minScale + (maxScale - minScale) * CGFloat(t))
                    .opacity(minOpacity + (maxOpacity - minOpacity) * t)
            }
        }
    }
}

// MARK: - Row appearance (non-layout transform)

/// Soft entrance for a newly inserted **streaming** row.
///
/// Intentionally does **not** animate user messages (instant paint on send).
/// Offset-only motion was also disabled for streaming: the 6pt settle fought
/// the table's bottom-pin on insert and contributed to "history jumps" on
/// send. Keep the modifier as a no-op gate so call sites stay stable.
struct JinMessageAppearModifier: ViewModifier {
    let shouldAnimate: Bool

    func body(content: Content) -> some View {
        // Appear motion is intentionally identity — pin/height coalescing owns
        // send smoothness; offset animations here caused scroll fighting.
        // Keep `shouldAnimate` in the type for API stability at call sites.
        let _ = shouldAnimate
        return content
    }
}

extension View {
    /// Soft settle for a just-inserted streaming row (not user messages).
    func jinMessageAppear(enabled: Bool) -> some View {
        modifier(JinMessageAppearModifier(shouldAnimate: enabled))
    }
}
