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

extension ChatView {
    var conversationStage: some View {
        Group {
            if isArtifactPaneVisible {
                HSplitView {
                    messageStageContainer
                    artifactPane
                }
            } else {
                messageStageContainer
            }
        }
        .onChange(of: conversationEntity.activeThreadID) { _, _ in
            syncArtifactSelectionForActiveThread()
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
            catalog: activeArtifactCatalog,
            selectedArtifactID: selectedArtifactIDBinding,
            selectedArtifactVersion: selectedArtifactVersionBinding,
            onClose: {
                isArtifactPaneVisible = false
            }
        )
    }

    var messageStage: some View {
        GeometryReader { geometry in
            if panelThreads.count > 1 {
                multiThreadMessageStage(geometry: geometry)
            } else {
                singleThreadMessageStage(geometry: geometry)
            }
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

        return ChatSingleThreadMessagesView(
            conversationID: conversationEntity.id,
            conversationMessageCount: renderCache.cachedTotalMessageCount,
            renderRevision: renderCache.version,
            containerSize: geometry.size,
            visibleContainerWidth: visibleContainerWidth,
            layoutCenterOffset: layoutCenterOffset,
            allMessages: singleThreadRenderContext.visibleMessages,
            toolResultsByCallID: singleThreadRenderContext.toolResultsByCallID,
            messageEntitiesByID: singleThreadRenderContext.messageEntitiesByID,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: currentProviderIconID,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: activeModelThread.flatMap { streamingModelID(for: $0.id) },
            messageRenderPageSize: Self.messageRenderPageSize,
            eagerCodeHighlightTailCount: Self.eagerCodeHighlightTailCount,
            nonLazyMessageStackThreshold: Self.nonLazyMessageStackThreshold,
            pinnedBottomRefreshDelays: Self.pinnedBottomRefreshDelays,
            interaction: messageInteractionContext,
            onStreamingFinished: {
                rebuildMessageCachesIfNeeded()
            },
            onActivateMessageThread: { threadID in
                activateThread(by: threadID)
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

    func multiThreadMessageStage(geometry: GeometryProxy) -> some View {
        let visibleContainerWidth = ChatConversationLayoutMetrics.visibleContainerWidth(
            containerWidth: geometry.size.width,
            sidebarWidth: mainSidebarWidth,
            isSidebarHidden: isSidebarHidden
        )
        let layoutCenterOffset = ChatConversationLayoutMetrics.sidebarCompensationOffset(
            sidebarWidth: mainSidebarWidth,
            isSidebarHidden: isSidebarHidden,
            compensationRatio: sidebarCompensationRatio
        )

        return ChatMultiModelStageView(
            conversationMessageCount: renderCache.cachedTotalMessageCount,
            containerSize: geometry.size,
            visibleContainerWidth: visibleContainerWidth,
            layoutCenterOffset: layoutCenterOffset,
            threads: panelThreads,
            contextsByThreadID: panelThreadRenderContexts,
            assistantDisplayName: assistantDisplayName,
            composerHeight: composerHeight,
            isStreaming: isStreaming,
            activeThreadID: activeModelThread?.id,
            initialMessageRenderLimit: Self.initialMessageRenderLimit,
            messageRenderPageSize: Self.messageRenderPageSize,
            eagerCodeHighlightTailCount: Self.eagerCodeHighlightTailCount,
            nonLazyMessageStackThreshold: Self.nonLazyMessageStackThreshold,
            interaction: messageInteractionContext,
            modelNameForThread: { thread in
                modelName(id: thread.modelID, providerID: thread.providerID)
            },
            providerTypeForThread: { thread in
                providerType(forProviderID: thread.providerID)
            },
            providerIconIDForProviderID: { providerID in
                providerIconID(for: providerID)
            },
            streamingMessageForThread: { threadID in
                streamingMessage(for: threadID)
            },
            streamingModelLabelForThread: { threadID in
                streamingModelLabel(for: threadID)
            },
            streamingModelIDForThread: { threadID in
                streamingModelID(for: threadID)
            },
            errorMessageForThread: { threadID in
                streamingStore.error(conversationID: conversationEntity.id, threadID: threadID)
            },
            onActivateThread: { threadID in
                activateThread(by: threadID)
            },
            onRetryThread: { threadID in
                streamingStore.clearError(conversationID: conversationEntity.id, threadID: threadID)
                startStreamingResponse(for: threadID)
            },
            onDismissThreadError: { threadID in
                streamingStore.clearError(conversationID: conversationEntity.id, threadID: threadID)
            },
            onOpenArtifact: openArtifact,
            expandedCollapsedMessageIDs: $expandedCollapsedMessageIDs
        )
    }
}
