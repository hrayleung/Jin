import SwiftUI

private struct MessageTimelineContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ChatSingleThreadMessagesContentView: View, Equatable {
    let key: ChatStageEquatableKey
    let conversationID: UUID
    let visibleMessagesForWindow: [MessageRenderItem]
    let allMessageCount: Int
    let messageRenderPageSize: Int
    let eagerCodeHighlightTailCount: Int
    let nonLazyMessageStackThreshold: Int
    let containerSize: CGSize
    let visibleContainerWidth: CGFloat
    let layoutCenterOffset: CGFloat
    let composerHeight: CGFloat
    let isStreaming: Bool
    let streamingMessage: StreamingMessageState?
    let streamingModelLabel: String?
    let streamingModelID: String?
    let assistantDisplayName: String
    let providerType: ProviderType?
    let providerIconID: String?
    let toolResultsByCallID: [String: ToolResult]
    let messageEntitiesByID: [UUID: MessageEntity]
    let pinnedBottomRefreshDelays: [TimeInterval]
    let interaction: ChatMessageInteractionContext
    let onStreamingFinished: () -> Void
    let onActivateMessageThread: (UUID) -> Void
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void
    let timelineWindow: ChatMessageStagePresentationSupport.TimelineWindow
    let expandedCollapsedMessageIDs: Binding<Set<UUID>>
    @Binding var messageRenderLimit: Int
    @Binding var pendingRestoreScrollMessageID: UUID?
    @Binding var isPinnedToBottom: Bool
    @Binding var pinnedBottomRefreshGeneration: Int
    @Binding var lastMeasuredContentHeight: CGFloat
    @Binding var pendingPinnedBottomRefreshTask: Task<Void, Never>?
    @Binding var shouldMaintainPinnedBottomAnchor: Bool
    @Binding var isUserScrollInProgress: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }

    private var visibleMessages: [MessageRenderItem] {
        visibleMessagesForWindow
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let layout = ChatMessageStagePresentationSupport.SingleThreadLayout(
                    visibleContainerWidth: visibleContainerWidth
                )
                let window = timelineWindow

                Group {
                    if window.usesLazyStack {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            timelineView(
                                window: window,
                                bubbleMaxWidth: layout.bubbleMaxWidth
                            )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            timelineView(
                                window: window,
                                bubbleMaxWidth: layout.bubbleMaxWidth
                            )
                        }
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MessageTimelineContentHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                }
                .frame(width: layout.columnWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: layoutCenterOffset)
                .padding(.top, 24)
            }
            .overlayScrollerStyle()
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    Button {
                        shouldMaintainPinnedBottomAnchor = true
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollToBottomIfNeeded(proxy: proxy, allowWhenContentFits: true)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .jinAdaptiveBackground(Circle())
                            .shadow(color: JinSemanticColor.shadowElevated, radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPinnedToBottom)
            .onScrollPinChange(
                isPinned: $isPinnedToBottom,
                bottomTolerance: ChatTimelineScrollCoordinator.pinnedBottomTolerance(
                    composerHeight: composerHeight
                ),
                onChange: handlePinStateChange
            )
            .onUserScrollIntentChange { isUserDrivenScroll in
                isUserScrollInProgress = isUserDrivenScroll
            }
            .onChange(of: messageRenderLimit) { _, _ in
                guard let restoreID = pendingRestoreScrollMessageID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(restoreID, anchor: .top)
                    pendingRestoreScrollMessageID = nil
                }
            }
            .onChange(of: allMessageCount) { _, _ in
                refreshPinnedBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: isStreaming) { wasStreaming, nowStreaming in
                guard wasStreaming, !nowStreaming else { return }
                onStreamingFinished()
                refreshPinnedBottomIfNeeded(proxy: proxy)
            }
            .onChange(of: conversationID) { _, _ in
                cancelPendingPinnedBottomRefresh()
                lastMeasuredContentHeight = 0
                shouldMaintainPinnedBottomAnchor = true
                isUserScrollInProgress = false
            }
            .onPreferenceChange(MessageTimelineContentHeightPreferenceKey.self) { newHeight in
                handleContentHeightChange(newHeight, proxy: proxy)
            }
            .onDisappear {
                cancelPendingPinnedBottomRefresh()
            }
        }
    }

    private func timelineView(
        window: ChatMessageStagePresentationSupport.TimelineWindow,
        bubbleMaxWidth: CGFloat
    ) -> some View {
        ChatMessageTimelineView(
            visibleMessages: window.visibleMessages,
            hiddenCount: window.hiddenCount,
            messageRenderPageSize: messageRenderPageSize,
            onLoadEarlier: {
                guard let plan = window.loadEarlierPlan else { return }
                pendingRestoreScrollMessageID = plan.restoreMessageID
                messageRenderLimit = plan.nextRenderLimit
            },
            bubbleMaxWidth: bubbleMaxWidth,
            assistantDisplayName: assistantDisplayName,
            providerType: providerType,
            providerIconID: providerIconID,
            eagerCodeHighlightStartIndex: window.eagerCodeHighlightStartIndex,
            toolResultsByCallID: toolResultsByCallID,
            messageEntitiesByID: messageEntitiesByID,
            interaction: interaction,
            streamingMessage: streamingMessage,
            streamingModelLabel: streamingModelLabel,
            streamingModelID: streamingModelID,
            bottomSpacerHeight: composerHeight + 24,
            bottomID: ChatMessageStagePresentationSupport.bottomAnchorID(),
            onActivateThreadForMessage: { threadID in
                guard let threadID else { return }
                onActivateMessageThread(threadID)
            },
            onActivateTimeline: { },
            onOpenArtifact: onOpenArtifact,
            effectiveRenderMode: effectiveRenderMode,
            onExpandCollapsedContent: expandCollapsedContent
        )
    }

    private func refreshPinnedBottomIfNeeded(proxy: ScrollViewProxy) {
        guard let plan = ChatTimelineScrollCoordinator.refreshPlan(
            currentGeneration: pinnedBottomRefreshGeneration,
            shouldMaintainPinnedBottomAnchor: shouldMaintainPinnedBottomAnchor,
            delays: pinnedBottomRefreshDelays
        ) else {
            return
        }
        pinnedBottomRefreshGeneration = plan.generation

        for delay in plan.delays {
            schedulePinnedBottomRefreshAttempt(
                after: delay,
                expectedGeneration: plan.generation,
                proxy: proxy
            )
        }
    }

    private func schedulePinnedBottomRefresh(
        proxy: ScrollViewProxy,
        debounceNanoseconds: UInt64? = nil
    ) {
        cancelPendingPinnedBottomRefresh()
        guard shouldMaintainPinnedBottomAnchor else { return }

        pendingPinnedBottomRefreshTask = Task { @MainActor in
            if let debounceNanoseconds {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }
            }

            refreshPinnedBottomIfNeeded(proxy: proxy)
            pendingPinnedBottomRefreshTask = nil
        }
    }

    private func schedulePinnedBottomRefreshAttempt(
        after delay: TimeInterval,
        expectedGeneration: Int,
        proxy: ScrollViewProxy
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard ChatTimelineScrollCoordinator.shouldPerformRefresh(
                expectedGeneration: expectedGeneration,
                currentGeneration: pinnedBottomRefreshGeneration,
                shouldMaintainPinnedBottomAnchor: shouldMaintainPinnedBottomAnchor
            ) else {
                return
            }
            scrollToBottomIfNeeded(proxy: proxy)
        }
    }

    private func cancelPendingPinnedBottomRefresh() {
        pendingPinnedBottomRefreshTask?.cancel()
        pendingPinnedBottomRefreshTask = nil
    }

    private func scrollToBottomIfNeeded(
        proxy: ScrollViewProxy,
        allowWhenContentFits: Bool = false
    ) {
        guard ChatTimelineScrollCoordinator.shouldScrollToBottom(
            lastMeasuredContentHeight: lastMeasuredContentHeight,
            viewportHeight: containerSize.height,
            allowWhenContentFits: allowWhenContentFits
        ) else {
            return
        }
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    private func handleContentHeightChange(_ newHeight: CGFloat, proxy: ScrollViewProxy) {
        guard let action = ChatTimelineScrollCoordinator.contentHeightChangeAction(
            newHeight: newHeight,
            previousHeight: lastMeasuredContentHeight,
            shouldMaintainPinnedBottomAnchor: shouldMaintainPinnedBottomAnchor
        ) else {
            return
        }
        lastMeasuredContentHeight = action.measuredHeight
        guard action.shouldScheduleRefresh else { return }
        schedulePinnedBottomRefresh(
            proxy: proxy,
            debounceNanoseconds: 120_000_000
        )
    }

    private func handlePinStateChange(wasPinned: Bool, isPinned: Bool) {
        guard wasPinned != isPinned else { return }

        if isPinned {
            shouldMaintainPinnedBottomAnchor = true
            return
        }

        guard isUserScrollInProgress else { return }
        cancelPendingPinnedBottomRefresh()
        shouldMaintainPinnedBottomAnchor = false
        pinnedBottomRefreshGeneration = ChatTimelineScrollCoordinator.invalidatedRefreshGeneration(
            current: pinnedBottomRefreshGeneration
        )
    }

    private func effectiveRenderMode(index: Int, message: MessageRenderItem) -> MessageRenderMode {
        ChatLongConversationRenderPolicy.effectiveRenderMode(
            index: index,
            message: message,
            totalMessageCount: allMessageCount,
            visibleMessageCount: visibleMessages.count,
            expandedIDs: expandedCollapsedMessageIDs.wrappedValue
        )
    }

    private func expandCollapsedContent(_ messageID: UUID) {
        expandedCollapsedMessageIDs.wrappedValue = ChatLongConversationRenderPolicy.expandedMessageIDs(
            byExpanding: messageID,
            from: expandedCollapsedMessageIDs.wrappedValue
        )
    }
}
