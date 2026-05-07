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
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let rect = CGRect(origin: .zero, size: size)
            let gradient = Gradient(stops: [
                .init(color: surfaceColor.opacity(0), location: 0),
                .init(color: surfaceColor.opacity(0.10), location: 0.24),
                .init(color: surfaceColor.opacity(0.34), location: 0.58),
                .init(color: surfaceColor.opacity(0.72), location: 0.84),
                .init(color: surfaceColor, location: 1)
            ])

            context.fill(
                Path(rect),
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )
        }
        .frame(height: fadeHeight)
        .frame(maxWidth: .infinity)
        .opacity(isExpandedComposerPresented ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        .onChange(of: activeThreadID) { _, _ in
            syncArtifactSelectionForActiveThread()
        }
        .onPreferenceChange(ComposerHeightPreferenceKey.self) { newValue in
            let normalizedHeight = ChatStageBottomFadeMetrics.normalizedComposerHeight(newValue)
            if composerHeight != normalizedHeight {
                composerHeight = normalizedHeight
            }
        }
        .background(JinSemanticColor.detailSurface)
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
            surfaceColor: JinSemanticColor.detailSurface,
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
            if selectedModelThreads.count > 1 {
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
            conversationMessageCount: conversationEntity.messages.count,
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
            streamingModelID: activeThreadID.flatMap { streamingModelID(for: $0) },
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
        .animation(.easeInOut(duration: 0.24), value: mainSidebarWidth)
    }

    var sidebarCompensationRatio: CGFloat {
        mainWindowIsFullScreen
            ? ChatConversationLayoutMetrics.fullScreenSidebarCompensationRatio
            : ChatConversationLayoutMetrics.standardSidebarCompensationRatio
    }

    func multiThreadMessageStage(geometry: GeometryProxy) -> some View {
        ChatMultiModelStageView(
            conversationMessageCount: conversationEntity.messages.count,
            containerSize: geometry.size,
            threads: selectedModelThreads,
            contextsByThreadID: selectedThreadRenderContexts,
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
            onActivateThread: { threadID in
                activateThread(by: threadID)
            },
            onOpenArtifact: openArtifact,
            expandedCollapsedMessageIDs: $expandedCollapsedMessageIDs
        )
    }
}
