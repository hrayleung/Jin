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
    let onOpenArtifact: (RenderedArtifactVersion) -> Void
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

    /// Set while we are driving `proxy.scrollTo(...)` ourselves. During a
    /// programmatic scroll the scroll-geometry stream emits transient
    /// off-pin offsets that must not be treated as a user-initiated unpin.
    /// We do NOT key on `isUserScrollInProgress` because SwiftUI fires
    /// `onScrollGeometryChange` *before* `onScrollPhaseChange` flips to
    /// `.tracking` for the first user gesture — that race left the pin stuck
    /// true and immediately snapped the user's scroll back to bottom.
    @State private var isExecutingProgrammaticScroll = false

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
                // Any user-initiated scroll — even 1 pt, even within
                // `pinnedBottomTolerance` — is an explicit signal that the
                // user does NOT want the chat to snap them back to bottom.
                // Without this, a tiny trackpad nudge keeps `isPinnedToBottom`
                // true (the 36 pt tolerance window) which keeps anchor true,
                // and the next content-height change (e.g. tapping to expand
                // a Web Search / MCP / code-exec card) immediately snaps the
                // scroll position to the new bottom.
                if isUserDrivenScroll {
                    cancelPendingPinnedBottomRefresh()
                    shouldMaintainPinnedBottomAnchor = false
                    pinnedBottomRefreshGeneration = ChatTimelineScrollCoordinator.invalidatedRefreshGeneration(
                        current: pinnedBottomRefreshGeneration
                    )
                }
            }
            .onChange(of: messageRenderLimit) { _, _ in
                guard let restoreID = pendingRestoreScrollMessageID else { return }
                DispatchQueue.main.async {
                    beginProgrammaticScroll()
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
        beginProgrammaticScroll()
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    /// Mark the next ~400 ms as "programmatic scroll territory" so that the
    /// mid-flight off-pin geometry samples emitted by SwiftUI during the
    /// snap-down animation don't get interpreted as a user unpin.
    private func beginProgrammaticScroll() {
        isExecutingProgrammaticScroll = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            isExecutingProgrammaticScroll = false
        }
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
        // We're already mid-flight of a programmatic scroll-to-bottom; the
        // animation itself is what's causing this height change to fire over
        // and over. Letting each frame re-arm a 120 ms task creates a stacked
        // chain of refresh attempts that fight the user when they try to do
        // anything during the spring window. Skip until the programmatic
        // window clears.
        guard !isExecutingProgrammaticScroll else { return }
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

        // Trust the geometry: when the scroll view is no longer near the
        // bottom, the pin is broken. The only legitimate reason to *ignore*
        // an off-pin geometry sample is that we, the code, are mid-flight
        // of a programmatic scroll-to-bottom animation. We do NOT gate on
        // `isUserScrollInProgress` because SwiftUI fires the geometry
        // change before the `.tracking` phase, so the first user gesture
        // would otherwise be silently dropped.
        guard !isExecutingProgrammaticScroll else { return }
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
