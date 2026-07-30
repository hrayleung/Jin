import SwiftUI

// MARK: - Public API

/// Timeline disclosure expand/collapse — height curtain with a stable view tree.
///
/// ## Why this is picky
///
/// The panel lives inside an `NSTableView` row whose height is driven by
/// `NSHostingView.fittingSize` → `noteHeightOfRows`. If SwiftUI animates height
/// with a spring, every micro-correction remeasures the row, the table
/// repositions every row below, and scroll-anchor compensation may also fire.
/// That stack reads as **jitter**.
///
/// ## Contract
///
/// 1. **One stable child identity** — never branch the view tree on measure
///    state (that reset `Animatable` from-values and popped).
/// 2. **Finite height only** — `0 ↔ measured`, never `.infinity`.
/// 3. **Fixed-duration easeInOut** — pair with `JinMotion.disclosure(expanding:)`
///    so the table can match the same wall-clock window.
/// 4. **Child does not reflow** — `fixedSize` + top-aligned clip (curtain).
/// 5. **No opacity / compositingGroup** — those caused ghosting earlier.
///
/// Drive `isExpanded` with `withAnimation(JinMotion.disclosure(expanding:))`.
/// Lazy-mount call sites keep their own `hasEverExpanded` latch.
struct JinCollapsibleContent<Content: View>: View {
    let isExpanded: Bool
    @State private var measuredHeight: CGFloat = 0
    @ViewBuilder private let content: () -> Content

    init(
        isExpanded: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
        self.content = content
    }

    /// Legacy overload — `fades` is ignored (opacity expand caused ghosting).
    init(
        isExpanded: Bool,
        fades: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
        self.content = content
        _ = fades
    }

    var body: some View {
        content()
            // Height animation is owned by `AnimatableHeightClip` only.
            .transaction { $0.animation = nil }
            .fixedSize(horizontal: false, vertical: true)
            .background(heightProbe)
            .onPreferenceChange(CollapsibleContentHeightKey.self, perform: storeMeasuredHeight)
            // Always the same modifier identity so `animatableData` can
            // interpolate from the previous height (no Group/if branch).
            .modifier(AnimatableHeightClip(height: clipHeight))
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
    }

    /// Expanded + not yet measured: use 0 until the probe lands (first-expand
    /// call sites mount collapsed for one frame so the probe is ready before
    /// the spring runs). Collapsed always 0.
    private var clipHeight: CGFloat {
        guard isExpanded else { return 0 }
        return max(0, measuredHeight)
    }

    private var heightProbe: some View {
        // Sits inside `fixedSize` and outside the clip frame, so it keeps
        // reporting the ideal height while the outer clip animates.
        GeometryReader { proxy in
            Color.clear.preference(
                key: CollapsibleContentHeightKey.self,
                value: proxy.size.height
            )
        }
    }

    private func storeMeasuredHeight(_ newHeight: CGFloat) {
        // Ignore near-zero samples while fully collapsed so the next expand
        // still has a solid target. Never animate measure writes — they must
        // not retarget an in-flight height spring.
        guard newHeight > 1 else { return }
        guard abs(newHeight - measuredHeight) > 0.5 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            measuredHeight = newHeight
        }
    }
}

// MARK: - Rotating disclosure chevron

/// SF Symbol chevron that rotates 90° instead of swapping glyphs.
struct JinDisclosureChevron: View {
    let isExpanded: Bool
    var font: Font = .caption2.weight(.semibold)
    var foregroundStyle: Color = JinSemanticColor.textTertiary

    var body: some View {
        Image(systemName: "chevron.right")
            .font(font)
            .foregroundStyle(foregroundStyle)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(JinMotion.disclosureIndicator, value: isExpanded)
            .frame(width: 8, height: 10, alignment: .center)
            .contentShape(Rectangle())
    }
}

// MARK: - Internals

/// Clips a full-size child to an animatable finite height (curtain reveal).
///
/// Intermediate heights publish into the layout system each frame so the
/// timeline row can track — the table controller coalesces those reports so
/// they do not thrash `noteHeightOfRows` multiple times per frame.
private struct AnimatableHeightClip: ViewModifier, Animatable {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(height: max(0, height), alignment: .top)
            .clipped()
    }
}

private enum CollapsibleContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
