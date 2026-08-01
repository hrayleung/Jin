import SwiftUI

/// The conversation minimap: a column of thin tick marks floating over the left
/// edge of the transcript, one per turn. Hovering a tick reveals a card with
/// that turn's question and the start of its answer; clicking scrolls there.
///
/// This view owns no transcript state. Turns arrive as a plain value (recomputed
/// only when the stage's equatable key changes) and the scroll position arrives
/// through `ChatConversationMinimapModel`, which publishes only when the active
/// turn actually changes — so scrolling and streaming never re-render the
/// transcript underneath.
struct ChatConversationMinimapRail: View {
    let turnList: ChatConversationMinimapGeometry.TurnList
    let assistantDisplayName: String
    /// Observed here and ONLY here: the active-turn tick is the one piece of
    /// scroll-frequency state, and its publishes must re-render just the rail
    /// (the stage view owns the outer model as `@StateObject`, which must
    /// never publish — see `ChatConversationMinimapModel`).
    @ObservedObject var railState: ChatConversationMinimapRailState
    let onJump: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredTurnIndex: Int?
    @State private var isRailHovered = false
    @State private var cardHeight: CGFloat = 0

    private static let railWidth: CGFloat = 34
    private static let cardWidth: CGFloat = 328
    private static let cardGap: CGFloat = 12
    private static let tickHeight: CGFloat = 3
    private static let fallbackCardHeight: CGFloat = 140
    private static let cardCornerRadius = JinRadius.large

    private let pitch = ChatConversationMinimapGeometry.tickPitch

    private var turns: [ChatConversationMinimapGeometry.Turn] { turnList.turns }

    private var activeTurnIndex: Int? {
        turnList.turnIndex(forMessageID: railState.activeMessageID)
    }

    private var assistantRoleLabel: String {
        ChatConversationMinimapGeometry.assistantRoleLabel(displayName: assistantDisplayName)
    }

    var body: some View {
        if turns.isEmpty {
            EmptyView()
        } else {
            railBody
        }
    }

    private var railBody: some View {
        GeometryReader { geometry in
            let layout = ChatConversationMinimapGeometry.layout(
                turnCount: turns.count,
                activeIndex: activeTurnIndex,
                availableHeight: geometry.size.height,
                pitch: pitch
            )

            ZStack(alignment: .topLeading) {
                tickColumn(layout: layout)
                hoverCard(layout: layout, viewportHeight: geometry.size.height)
            }
            .frame(
                width: Self.railWidth + Self.cardGap + Self.cardWidth,
                height: geometry.size.height,
                alignment: .topLeading
            )
            // On the container, not inside the `if` — a transition only plays
            // when an animation is attached to a view present on both sides of
            // the insertion.
            .animation(cardAnimation, value: hoveredTurnIndex)
            .onPreferenceChange(ChatConversationMinimapCardHeightKey.self) { height in
                // Guard identical heights so continuous hover doesn't thrash layout.
                if abs(cardHeight - height) > 0.5 {
                    cardHeight = height
                }
            }
        }
        .frame(width: Self.railWidth + Self.cardGap + Self.cardWidth)
    }

    // MARK: - Ticks

    /// One hit region for the whole column rather than a control per tick.
    ///
    /// Ticks are 2pt tall inside a 10pt slot; per-tick hover targets that small
    /// are miserable to land on, and the pointer would fall through the gaps.
    /// A single strip plus `onContinuousHover` means anywhere in the rail picks
    /// the tick at that height.
    ///
    /// Centred by LAYOUT (`maxHeight: .infinity, alignment: .center`), never by
    /// `.offset` — an offset moves what you see but leaves the hit region at the
    /// un-offset layout position, so the ticks look right and answer to nothing.
    private func tickColumn(layout: ChatConversationMinimapGeometry.Layout) -> some View {
        let railHeight = CGFloat(layout.visibleRange.count) * pitch

        return VStack(spacing: 0) {
            ForEach(layout.visibleRange, id: \.self) { index in
                tick(at: index, layout: layout)
            }
        }
        .frame(width: Self.railWidth, height: railHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                // Only publish when something actually changed — continuous
                // hover fires on every mouse move, and writing identical
                // `@State` would re-evaluate the whole rail for free.
                if !isRailHovered { isRailHovered = true }
                let next = turnIndex(atY: point.y, layout: layout)
                if hoveredTurnIndex != next {
                    hoveredTurnIndex = next
                }
            case .ended:
                if isRailHovered { isRailHovered = false }
                if hoveredTurnIndex != nil { hoveredTurnIndex = nil }
            @unknown default:
                if isRailHovered { isRailHovered = false }
                if hoveredTurnIndex != nil { hoveredTurnIndex = nil }
            }
        }
        .onTapGesture { point in
            guard let index = turnIndex(atY: point.y, layout: layout), index < turns.count else { return }
            onJump(turns[index].id)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Conversation minimap")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Hover a marker to preview a turn, click it to scroll there.")
        // The hit shape above belongs to the tick block itself; this outer
        // frame only centres that block in the available height.
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.15), value: isRailHovered)
    }

    private func tick(at index: Int, layout: ChatConversationMinimapGeometry.Layout) -> some View {
        let isActive = activeTurnIndex == index
        let isHovered = hoveredTurnIndex == index

        return Capsule(style: .continuous)
            .fill(isActive ? Color.primary : JinSemanticColor.textTertiary)
            .frame(width: tickWidth(isActive: isActive, isHovered: isHovered), height: Self.tickHeight)
            // The active tick stays legible even at rest — it doubles as the
            // "you are here" marker, so it must not fade with the rest.
            .opacity(restOpacity(isActive: isActive) * endFade(at: index, layout: layout))
            .frame(width: Self.railWidth, height: pitch, alignment: .leading)
            .animation(.easeInOut(duration: 0.15), value: isActive)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    /// Which turn sits at `y` within the tick block.
    private func turnIndex(
        atY y: CGFloat,
        layout: ChatConversationMinimapGeometry.Layout
    ) -> Int? {
        let slot = Int((y / pitch).rounded(.down))
        guard slot >= 0, slot < layout.visibleRange.count else { return nil }
        return layout.visibleRange.lowerBound + slot
    }

    private func tickWidth(isActive: Bool, isHovered: Bool) -> CGFloat {
        if isActive { return 24 }
        return isHovered ? 20 : 15
    }

    private func restOpacity(isActive: Bool) -> Double {
        if isActive { return 1 }
        return isRailHovered ? 0.9 : 0.45
    }

    /// Softens the two end ticks when the rail is showing a sliding window, to
    /// signal there are more turns that way. Done per tick rather than with a
    /// `.mask` gradient, because a mask also clips hit testing.
    private func endFade(at index: Int, layout: ChatConversationMinimapGeometry.Layout) -> Double {
        let position = index - layout.visibleRange.lowerBound
        let count = layout.visibleRange.count
        if layout.fadesTop, position < 2 { return position == 0 ? 0.25 : 0.6 }
        if layout.fadesBottom, position >= count - 2 { return position == count - 1 ? 0.25 : 0.6 }
        return 1
    }

    private func railTop(railHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(0, (viewportHeight - railHeight) / 2)
    }

    // MARK: - Hover preview

    @ViewBuilder
    private func hoverCard(
        layout: ChatConversationMinimapGeometry.Layout,
        viewportHeight: CGFloat
    ) -> some View {
        if let hoveredTurnIndex,
           layout.visibleRange.contains(hoveredTurnIndex),
           hoveredTurnIndex < turns.count {
            EquatableView(
                content: ChatConversationMinimapPreviewCard(
                    turn: turns[hoveredTurnIndex],
                    assistantRoleLabel: assistantRoleLabel,
                    cardWidth: Self.cardWidth,
                    cornerRadius: Self.cardCornerRadius
                )
            )
            .offset(
                x: Self.railWidth + Self.cardGap,
                y: cardY(for: hoveredTurnIndex, layout: layout, viewportHeight: viewportHeight)
            )
            .transition(cardTransition)
        }
    }

    private var cardAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.08)
        }
        return .spring(response: 0.28, dampingFraction: 0.86)
    }

    private var cardTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .leading))
                .combined(with: .offset(x: -6)),
            removal: .opacity
                .combined(with: .scale(scale: 0.98, anchor: .leading))
        )
    }

    /// Centres the card on its tick, then clamps it inside the viewport so a
    /// turn near either end still shows the whole card.
    private func cardY(
        for index: Int,
        layout: ChatConversationMinimapGeometry.Layout,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let railHeight = CGFloat(layout.visibleRange.count) * pitch
        let offsetInRail = CGFloat(index - layout.visibleRange.lowerBound)
        let tickCenterY = railTop(railHeight: railHeight, viewportHeight: viewportHeight)
            + (offsetInRail + 0.5) * pitch
        let height = cardHeight > 0 ? cardHeight : Self.fallbackCardHeight
        return min(max(tickCenterY - height / 2, 0), max(0, viewportHeight - height))
    }

    private var accessibilityValue: String {
        guard let activeTurnIndex else { return "\(turns.count) turns" }
        return "Turn \(activeTurnIndex + 1) of \(turns.count)"
    }
}

// MARK: - Preview card

/// Isolated equatable card so hover-index changes that land on the same turn
/// content don't rebuild the material + text stack.
private struct ChatConversationMinimapPreviewCard: View, Equatable {
    let turn: ChatConversationMinimapGeometry.Turn
    let assistantRoleLabel: String
    let cardWidth: CGFloat
    let cornerRadius: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.turn == rhs.turn
            && lhs.assistantRoleLabel == rhs.assistantRoleLabel
            && lhs.cardWidth == rhs.cardWidth
            && lhs.cornerRadius == rhs.cornerRadius
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if !turn.userExcerpt.isEmpty {
                section(
                    label: ChatConversationMinimapGeometry.userRoleLabel,
                    text: turn.userExcerpt,
                    lineLimit: 3
                )
            }
            if !turn.assistantExcerpt.isEmpty {
                section(
                    label: assistantRoleLabel,
                    text: turn.assistantExcerpt,
                    lineLimit: 5
                )
            }
            if turn.userExcerpt.isEmpty, turn.assistantExcerpt.isEmpty {
                Text("No text in this turn")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, JinSpacing.medium + 2)
        .padding(.vertical, JinSpacing.medium)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChatConversationMinimapCardHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
        // One static material treatment — hover is expressed by the card
        // appearing at all, never by swapping this for a solid colour.
        .jinAdaptiveBackground(shape, material: .regularMaterial)
        .clipShape(shape)
        .overlay(shape.stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.hairline))
        // Soft dual shadow reads as a floating macOS card without the hard
        // single-layer cut that a large elevated-only radius produces.
        .shadow(color: JinSemanticColor.shadowSubtle, radius: 2, x: 0, y: 1)
        .shadow(color: JinSemanticColor.shadowElevated, radius: 16, x: 0, y: 6)
        // Purely informational: it must never swallow a click meant for the
        // message underneath it.
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func section(label: String, text: String, lineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .jinSectionHeader()
                .foregroundStyle(JinSemanticColor.textTertiary)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if !turn.userExcerpt.isEmpty {
            parts.append("\(ChatConversationMinimapGeometry.userRoleLabel): \(turn.userExcerpt)")
        }
        if !turn.assistantExcerpt.isEmpty {
            parts.append("\(assistantRoleLabel): \(turn.assistantExcerpt)")
        }
        return parts.isEmpty ? "No text in this turn" : parts.joined(separator: ". ")
    }
}

struct ChatConversationMinimapCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
