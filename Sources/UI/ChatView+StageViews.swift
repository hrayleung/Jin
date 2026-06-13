import AppKit
import SwiftUI

// MARK: - Stage Views

enum ChatStageBottomFadeMetrics {
    static let hiddenComposerHeight: CGFloat = 64
    static let minimumVisibleComposerHeight: CGFloat = 88
    static let visibleComposerExtraHeight: CGFloat = 20
    static let maximumFadeHeight: CGFloat = 180

    static func normalizedComposerHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return 0 }
        return max(0, height.rounded(.toNearestOrAwayFromZero))
    }

    static func composerHeightUpdate(
        currentHeight: CGFloat,
        measuredHeight: CGFloat,
        isComposerHidden: Bool
    ) -> CGFloat? {
        let normalizedHeight = normalizedComposerHeight(measuredHeight)

        if !isComposerHidden, currentHeight > 0, normalizedHeight == 0 {
            return nil
        }

        guard currentHeight != normalizedHeight else { return nil }
        return normalizedHeight
    }

    static func fadeHeight(composerHeight: CGFloat, isComposerHidden: Bool) -> CGFloat {
        let baseHeight = isComposerHidden
            ? hiddenComposerHeight
            : max(minimumVisibleComposerHeight, composerHeight + visibleComposerExtraHeight)

        return min(maximumFadeHeight, baseHeight)
    }
}

private struct ChatStageBottomFadeView: View {
    let surfaceColor: Color
    let composerHeight: CGFloat
    let isComposerHidden: Bool
    let isExpandedComposerPresented: Bool

    private var fadeHeight: CGFloat {
        ChatStageBottomFadeMetrics.fadeHeight(
            composerHeight: composerHeight,
            isComposerHidden: isComposerHidden
        )
    }

    var body: some View {
        StableBottomFadeGradientView(surfaceColor: surfaceColor)
        .frame(height: fadeHeight)
        .frame(maxWidth: .infinity)
        .opacity(isExpandedComposerPresented ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StableBottomFadeGradientView: NSViewRepresentable {
    let surfaceColor: Color

    func makeNSView(context: Context) -> StableBottomFadeGradientNSView {
        let view = StableBottomFadeGradientNSView()
        view.surfaceColor = NSColor(surfaceColor)
        return view
    }

    func updateNSView(_ nsView: StableBottomFadeGradientNSView, context: Context) {
        nsView.surfaceColor = NSColor(surfaceColor)
    }
}

private final class StableBottomFadeGradientNSView: NSView {
    var surfaceColor: NSColor = .windowBackgroundColor {
        didSet {
            updateGradientColors()
        }
    }

    override var isFlipped: Bool { true }

    private var gradientLayer: CAGradientLayer {
        guard let layer = layer as? CAGradientLayer else {
            let gradientLayer = CAGradientLayer()
            self.layer = gradientLayer
            return gradientLayer
        }
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CAGradientLayer()
        updateGradientConfiguration()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGradientColors()
    }

    private func updateGradientConfiguration() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let gradientLayer = gradientLayer
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.locations = [0, 0.24, 0.58, 0.84, 1]
        updateGradientColorsInsideCurrentTransaction()

        CATransaction.commit()
    }

    private func updateGradientColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateGradientColorsInsideCurrentTransaction()
        CATransaction.commit()
    }

    private func updateGradientColorsInsideCurrentTransaction() {
        var resolvedColor = surfaceColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = surfaceColor.usingColorSpace(.sRGB) ?? surfaceColor
        }
        gradientLayer.colors = [
            resolvedColor.withAlphaComponent(0).cgColor,
            resolvedColor.withAlphaComponent(0.10).cgColor,
            resolvedColor.withAlphaComponent(0.34).cgColor,
            resolvedColor.withAlphaComponent(0.72).cgColor,
            resolvedColor.cgColor
        ]
    }
}

/// Manual replacement for the artifact pane's `HSplitView` divider (see the
/// comment in `conversationStage`). A 1pt separator with a wider invisible
/// hit area; dragging resizes the trailing artifact pane within the same
/// bounds `ArtifactWorkspaceView` declares for itself.
private struct ChatArtifactPaneDivider: View {
    @Binding var paneWidth: CGFloat

    @State private var dragStartWidth: CGFloat?
    @State private var isCursorPushed = false

    static let minPaneWidth: CGFloat = 380
    static let maxPaneWidth: CGFloat = 820

    var body: some View {
        Rectangle()
            .fill(JinSemanticColor.separator.opacity(0.6))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover(perform: updateCursor)
                    .gesture(dragGesture)
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let base = dragStartWidth ?? paneWidth
                if dragStartWidth == nil { dragStartWidth = base }
                // The pane is trailing: dragging left (negative translation)
                // grows it.
                paneWidth = min(
                    max(base - value.translation.width, Self.minPaneWidth),
                    Self.maxPaneWidth
                )
            }
            .onEnded { _ in
                dragStartWidth = nil
            }
    }

    private func updateCursor(_ hovering: Bool) {
        if hovering, !isCursorPushed {
            NSCursor.resizeLeftRight.push()
            isCursorPushed = true
        } else if !hovering, isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
    }
}

extension ChatView {
    var conversationStage: some View {
        Group {
            if isArtifactPaneVisible {
                // NOT an HSplitView: inside NavigationSplitView's detail on
                // macOS 26 (Tahoe), Liquid Glass renders HSplitView's trailing
                // pane as a floating card that overlaps the chat instead of
                // splitting it, the divider isn't draggable, and the pane
                // header (with the close button) is clipped. A plain HStack
                // with a manual drag handle keeps the system chrome out of it.
                HStack(spacing: 0) {
                    messageStageContainer
                    ChatArtifactPaneDivider(paneWidth: $artifactPaneWidth)
                    artifactPane
                        .frame(width: artifactPaneWidth)
                }
            } else {
                messageStageContainer
            }
        }
        .onPreferenceChange(ComposerHeightPreferenceKey.self) { newValue in
            guard let nextHeight = ChatStageBottomFadeMetrics.composerHeightUpdate(
                currentHeight: composerHeight,
                measuredHeight: newValue,
                isComposerHidden: isComposerHidden
            ) else {
                return
            }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                composerHeight = nextHeight
            }
        }
        .background(JinSemanticColor.surface)
        .animation(.easeInOut(duration: 0.18), value: isArtifactPaneVisible)
    }

    var messageStageContainer: some View {
        ZStack(alignment: .bottom) {
            messageStage
            messageStageBottomFade
            floatingComposer
        }
    }

    @ViewBuilder
    var messageStageBottomFade: some View {
        ChatStageBottomFadeView(
            surfaceColor: JinSemanticColor.surface,
            composerHeight: composerHeight,
            isComposerHidden: isComposerHidden,
            isExpandedComposerPresented: isExpandedComposerPresented
        )
    }

    var artifactPane: some View {
        ArtifactWorkspaceView(
            catalog: renderCache.artifactCatalog,
            selectedArtifactID: $selectedArtifactID,
            selectedArtifactVersion: $selectedArtifactVersion,
            onClose: {
                isArtifactPaneVisible = false
            }
        )
    }

    var messageStage: some View {
        GeometryReader { geometry in
            singleThreadMessageStage(geometry: geometry)
        }
        .environment(\.googleMapsLocationBias, googleMapsLocationBiasValue)
    }

    func singleThreadMessageStage(geometry: GeometryProxy) -> some View {
        let visibleContainerWidth = ChatConversationLayoutMetrics.visibleContainerWidth(
            containerWidth: geometry.size.width,
            sidebarWidth: mainSidebarWidth,
            isSidebarHidden: isSidebarHidden
        )
        let compensationRatio = sidebarCompensationRatio
        let layoutCenterOffset = ChatConversationLayoutMetrics.sidebarCompensationOffset(
            sidebarWidth: mainSidebarWidth,
            isSidebarHidden: isSidebarHidden,
            compensationRatio: compensationRatio
        )

        let renderContext = renderCache.singleThreadContext()

        return ChatSingleThreadMessagesView(
            conversationID: conversationEntity.id,
            conversationMessageCount: renderCache.cachedTotalMessageCount,
            renderRevision: renderCache.version,
            containerSize: geometry.size,
            visibleContainerWidth: visibleContainerWidth,
            layoutCenterOffset: layoutCenterOffset,
            allMessages: renderContext.visibleMessages,
            toolResultsByCallID: renderContext.toolResultsByCallID,
            messageEntitiesByID: renderContext.messageEntitiesByID,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: currentProviderIconID,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID,
            messageRenderPageSize: Self.messageRenderPageSize,
            eagerCodeHighlightTailCount: Self.eagerCodeHighlightTailCount,
            nonLazyMessageStackThreshold: Self.nonLazyMessageStackThreshold,
            pinnedBottomRefreshDelays: Self.pinnedBottomRefreshDelays,
            interaction: messageInteractionContext,
            onStreamingFinished: {
                rebuildMessageCachesIfNeeded()
            },
            onOpenArtifact: openArtifact,
            expandedCollapsedMessageIDs: $expandedCollapsedMessageIDs,
            messageRenderLimit: $messageRenderLimit,
            pendingRestoreScrollMessageID: $pendingRestoreScrollMessageID,
            isPinnedToBottom: $isPinnedToBottom,
            pinnedBottomRefreshGeneration: $pinnedBottomRefreshGeneration
        )
    }

    var sidebarCompensationRatio: CGFloat {
        mainWindowIsFullScreen
            ? ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
            : ChatConversationLayoutMetrics.standardSidebarCompensationRatio
    }
}
