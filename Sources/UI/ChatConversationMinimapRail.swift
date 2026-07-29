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
    @ObservedObject var model: ChatConversationMinimapModel
    let onJump: (UUID) -> Void

    @State private var hoveredTurnIndex: Int?
    @State private var isRailHovered = false
    @State private var cardHeight: CGFloat = 0

    private static let railWidth: CGFloat = 34
    private static let cardWidth: CGFloat = 320
    private static let cardGap: CGFloat = 10
    private static let tickHeight: CGFloat = 3
    private static let fallbackCardHeight: CGFloat = 130

    private let pitch = ChatConversationMinimapGeometry.tickPitch

    private var turns: [ChatConversationMinimapGeometry.Turn] { turnList.turns }

    private var activeTurnIndex: Int? {
        turnList.turnIndex(forMessageID: model.activeMessageID)
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
            .animation(.easeInOut(duration: 0.12), value: hoveredTurnIndex)
            .onPreferenceChange(ChatConversationMinimapCardHeightKey.self) { height in
                cardHeight = height
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
                isRailHovered = true
                hoveredTurnIndex = turnIndex(atY: point.y, layout: layout)
            case .ended:
                isRailHovered = false
                hoveredTurnIndex = nil
            @unknown default:
                isRailHovered = false
                hoveredTurnIndex = nil
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
            .animation(.easeInOut(duration: 0.15), value: isHovered)
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
            previewCard(turns[hoveredTurnIndex])
                .offset(
                    x: Self.railWidth + Self.cardGap,
                    y: cardY(for: hoveredTurnIndex, layout: layout, viewportHeight: viewportHeight)
                )
                .transition(.opacity)
        }
    }

    private func previewCard(_ turn: ChatConversationMinimapGeometry.Turn) -> some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.medium, style: .continuous)

        return VStack(alignment: .leading, spacing: JinSpacing.small) {
            if !turn.userExcerpt.isEmpty {
                cardSection(label: "You", text: turn.userExcerpt, lineLimit: 3, isPrimary: true)
            }
            if !turn.assistantExcerpt.isEmpty {
                cardSection(
                    label: assistantDisplayName,
                    text: turn.assistantExcerpt,
                    lineLimit: 4,
                    isPrimary: false
                )
            }
            if turn.userExcerpt.isEmpty, turn.assistantExcerpt.isEmpty {
                Text("No text in this turn")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .jinCardPadding()
        .frame(width: Self.cardWidth, alignment: .leading)
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
        .jinAdaptiveBackground(shape)
        .clipShape(shape)
        .overlay(shape.stroke(JinSemanticColor.borderEmphasized, lineWidth: JinStrokeWidth.hairline))
        .shadow(color: JinSemanticColor.shadowElevated, radius: 12, x: 0, y: 4)
        // Purely informational: it must never swallow a click meant for the
        // message underneath it.
        .allowsHitTesting(false)
    }

    private func cardSection(
        label: String,
        text: String,
        lineLimit: Int,
        isPrimary: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(JinSemanticColor.textTertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(isPrimary ? Color.primary : Color.secondary)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct ChatConversationMinimapCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
