import SwiftUI

// MARK: - Streaming idle placeholder

/// Elegant “still waiting for the first token” chrome for the streaming bubble.
///
/// Replaces the old `ProgressView` + caption pair, which read as a system
/// spinner dropped into a chat surface. This indicator is:
///
/// 1. **Time-based** (`TimelineView`) so hosting-view reconfigures cannot
///    freeze it mid-pose (same contract as `JinContinuousMotion`).
/// 2. **Layout-stable** — fixed min height so the bubble does not jump when
///    the first token arrives.
/// 3. **Reduce-Motion aware** — static mid pose, no continuous animation.
/// 4. **Typographically quiet** — secondary subheadline, not a caption spinner.
struct JinStreamingPlaceholder: View {
    /// Visible status copy. Keep short; motion carries most of the meaning.
    var label: String = "Generating"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// One comfortable line of chat chrome — keep the empty-row height estimate
    /// aligned with this so the first measure does not snap the pin.
    static let preferredMinHeight: CGFloat = 28

    var body: some View {
        // No trailing Spacer: inside macOS 27's ConstrainedWidth
        // (frame+fixedSize) a greedy Spacer can inflate the streaming bubble
        // into a tall empty plate while the activity cluster fails to paint —
        // the "blank Generating row" glitch. Hug content; the parent bubble
        // already expands to the column width.
        HStack(alignment: .center, spacing: JinSpacing.small) {
            activityCluster
            labelView
        }
        .frame(maxWidth: .infinity, minHeight: Self.preferredMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Activity cluster (cascading soft dots)

    private var activityCluster: some View {
        Group {
            if reduceMotion {
                staticDots
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    dots(at: context.date)
                }
            }
        }
        .frame(width: Self.clusterWidth, height: Self.clusterHeight, alignment: .center)
        // Soft pill so the cluster reads as one affordance, not three stray pixels.
        .background(
            Capsule(style: .continuous)
                .fill(clusterFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline)
        )
    }

    private var staticDots: some View {
        HStack(spacing: Self.dotSpacing) {
            ForEach(0..<Self.dotCount, id: \.self) { _ in
                Circle()
                    .fill(dotColor.opacity(0.55))
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
    }

    private func dots(at date: Date) -> some View {
        HStack(spacing: Self.dotSpacing) {
            ForEach(0..<Self.dotCount, id: \.self) { index in
                Circle()
                    .fill(dotColor)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .opacity(dotOpacity(at: date, index: index))
                    .scaleEffect(dotScale(at: date, index: index))
            }
        }
    }

    /// Soft cascade: each dot breathes in opacity + a tiny scale, staggered.
    /// No vertical bounce — that reads as a toy spinner inside a message bubble.
    private func dotOpacity(at date: Date, index: Int) -> Double {
        let period = Self.period
        let offset = Double(index) * Self.stagger * period
        let phase = JinContinuousMotion.phase(at: date, period: period, offset: offset)
        let t = (JinContinuousMotion.sine(phase: phase) + 1) * 0.5
        return 0.28 + 0.72 * t
    }

    private func dotScale(at date: Date, index: Int) -> CGFloat {
        let period = Self.period
        let offset = Double(index) * Self.stagger * period
        let phase = JinContinuousMotion.phase(at: date, period: period, offset: offset)
        let t = (JinContinuousMotion.sine(phase: phase) + 1) * 0.5
        return 0.82 + 0.18 * CGFloat(t)
    }

    // MARK: - Label

    @ViewBuilder
    private var labelView: some View {
        if reduceMotion {
            Text(label)
                .font(labelFont)
                .foregroundStyle(JinSemanticColor.textSecondary)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(labelGradient(at: context.date))
            }
        }
    }

    /// Slow horizontal sheen across the word — reads as “alive” without a
    /// system spinner. Pure function of time; cannot stick mid-frame.
    private func labelGradient(at date: Date) -> LinearGradient {
        let period = Self.labelPeriod
        let phase = JinContinuousMotion.phase(at: date, period: period)
        let center = phase
        let base = JinSemanticColor.textSecondary
        let peak = Color.primary.opacity(colorScheme == .dark ? 0.92 : 0.88)
        return LinearGradient(
            stops: [
                .init(color: base, location: 0),
                .init(color: base, location: max(0, center - 0.24)),
                .init(color: peak, location: center),
                .init(color: base, location: min(1, center + 0.24)),
                .init(color: base, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var labelFont: Font {
        .system(.subheadline, design: .default).weight(.medium)
    }

    private var dotColor: Color {
        JinSemanticColor.textSecondary
    }

    private var clusterFill: Color {
        // Slightly stronger than the bubble’s own subtle surface so the
        // activity capsule lifts without competing with the header.
        JinSemanticColor.quoteSurfaceStrong
    }

    // MARK: - Metrics

    private static let dotCount = 3
    private static let dotSize: CGFloat = 5
    private static let dotSpacing: CGFloat = 5
    private static let clusterHorizontalPadding: CGFloat = 10
    private static let clusterVerticalPadding: CGFloat = 7
    private static let period: TimeInterval = 1.05
    private static let labelPeriod: TimeInterval = 2.4
    private static let stagger: Double = 0.18

    private static var clusterWidth: CGFloat {
        let dots = CGFloat(dotCount) * dotSize + CGFloat(dotCount - 1) * dotSpacing
        return dots + clusterHorizontalPadding * 2
    }

    private static var clusterHeight: CGFloat {
        dotSize + clusterVerticalPadding * 2
    }
}
