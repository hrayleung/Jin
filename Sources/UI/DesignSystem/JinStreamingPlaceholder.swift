import SwiftUI

// MARK: - Streaming idle placeholder

/// Elegant “still waiting for the first token” chrome for the streaming bubble.
///
/// Replaces the old `ProgressView` + caption pair, which read as a system
/// spinner dropped into a chat surface. This indicator is:
///
/// 1. **Single motion owner** — the assistant header owns the turn's only
///    activity orb, so this row stays quiet and never duplicates it.
/// 2. **Layout-stable** — fixed min height so the bubble does not jump when
///    the first token arrives.
/// 3. **Typographically quiet** — secondary subheadline, not a caption spinner.
struct JinStreamingPlaceholder: View {
    /// Visible status copy. Keep short; motion carries most of the meaning.
    var label: String = "Generating"

    /// One comfortable line of chat chrome — keep the empty-row height estimate
    /// aligned with this so the first measure does not snap the pin.
    static let preferredMinHeight: CGFloat = 28

    var body: some View {
        // No trailing Spacer: inside macOS 27's ConstrainedWidth
        // (frame+fixedSize) a greedy Spacer can inflate the streaming bubble
        // into a tall empty plate while the activity cluster fails to paint —
        // the "blank Generating row" glitch. Hug content; the parent bubble
        // already expands to the column width.
        labelView
        .frame(maxWidth: .infinity, minHeight: Self.preferredMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Label

    private var labelView: some View {
        Text(label)
            .font(labelFont)
            .foregroundStyle(JinSemanticColor.textSecondary)
    }

    private var labelFont: Font {
        .system(.subheadline, design: .default).weight(.medium)
    }
}
