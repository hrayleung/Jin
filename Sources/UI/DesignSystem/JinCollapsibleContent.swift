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
/// ## Nested collapsibles
///
/// MCP nests collapsibles (list → per-call args/result). Height is measured
/// **locally** via `GeometryReader` → `@State` (not a bubbling PreferenceKey),
/// so an inner collapsible's ideal height cannot inflate an outer panel.
///
/// ## Smooth expand
///
/// Call sites should keep this view mounted while collapsed long enough for the
/// probe to land (`measuredHeight > 0`) **before** flipping `isExpanded`.
/// Expanding with a zero measure target snaps open when the probe arrives and
/// reads as text flicker. Nested size changes while already open animate with
/// the disclosure curve so parent panels ease instead of popping.
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
            .fixedSize(horizontal: false, vertical: true)
            .background(heightProbe)
            // Always the same modifier identity so `animatableData` can
            // interpolate from the previous height (no Group/if branch).
            .modifier(AnimatableHeightClip(height: clipHeight))
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
    }

    /// Expanded + not yet measured: use 0 until the probe lands (first-expand
    /// call sites mount collapsed so the probe is ready before the spring runs).
    /// Collapsed always 0.
    private var clipHeight: CGFloat {
        guard isExpanded else { return 0 }
        return max(0, measuredHeight)
    }

    private var heightProbe: some View {
        // Background GeometryReader is sized to the fixedSize content, so it
        // reports ideal height without PreferenceKey bubbling to ancestors.
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    storeMeasuredHeight(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, newHeight in
                    storeMeasuredHeight(newHeight)
                }
        }
    }

    private func storeMeasuredHeight(_ newHeight: CGFloat) {
        guard newHeight > 1 else { return }
        let previous = measuredHeight
        guard abs(newHeight - previous) > 0.5 else { return }

        // Collapsed: store target for next expand without animating the
        // (already zero) clip.
        if !isExpanded {
            applyMeasuredHeight(newHeight, animated: false)
            return
        }

        // Expanded but never measured: probe arrived after the expand click.
        // Animate 0 → H so content curtains in instead of snapping (the snap
        // was the main "text flicker" on first open).
        if previous < 1 {
            applyMeasuredHeight(newHeight, animated: true)
            return
        }

        // Already open: nested child size change (tool args open/close inside
        // MCP). Ease the outer curtain; skip sub-2pt noise.
        if abs(newHeight - previous) < 2 {
            applyMeasuredHeight(newHeight, animated: false)
            return
        }
        applyMeasuredHeight(newHeight, animated: true)
    }

    private func applyMeasuredHeight(_ newHeight: CGFloat, animated: Bool) {
        if animated {
            withAnimation(JinMotion.disclosureExpand) {
                measuredHeight = newHeight
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                measuredHeight = newHeight
            }
        }
    }
}

// MARK: - Rotating disclosure chevron

/// SF Symbol chevron that rotates 90° instead of swapping glyphs.
///
/// Uses fixed-duration ease (not a spring) so an interrupted transaction —
/// e.g. `NSHostingView` rootView swap mid-toggle — lands on a clean rest
/// angle rather than freezing halfway between 0° and 90°.
struct JinDisclosureChevron: View {
    let isExpanded: Bool
    var font: Font = .caption2.weight(.semibold)
    var foregroundStyle: Color = JinSemanticColor.textTertiary

    var body: some View {
        Image(systemName: "chevron.right")
            .font(font)
            .foregroundStyle(foregroundStyle)
            // Explicit angle + value-based animation; identity is stable so
            // SwiftUI interpolates the angle rather than swapping views.
            .rotationEffect(.degrees(isExpanded ? 90 : 0), anchor: .center)
            .animation(JinMotion.disclosureIndicator, value: isExpanded)
            .frame(width: 8, height: 10, alignment: .center)
            .contentShape(Rectangle())
            // Drawing in a fixed frame keeps the glyph from shifting the
            // header baseline while the angle interpolates.
            .compositingGroup()
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
