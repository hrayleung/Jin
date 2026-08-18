import Foundation
import Observation
import SwiftUI

struct ChatRenderCacheRebuildRequest {
    let conversationID: UUID
    let allMessages: [MessageEntity]
    let orderedMessages: [MessageEntity]
    let updatedAt: Date
    let fallbackModelLabel: String
    let artifactsEnabled: Bool
    let providerIconsByID: [String: String?]
}

/// `@Observable` (Observation framework) gives per-property read tracking so
/// views that only consume `version` aren't re-evaluated when `artifactCatalog`
/// changes, etc. Replaces the previous coarse `ObservableObject`/`@Published`
/// fan-out, which invalidated every consumer on every published mutation.
@Observable
@MainActor
final class ChatRenderCacheController {
    private(set) var visibleMessages: [MessageRenderItem] = []
    private(set) var version: Int = 0
    private(set) var messageEntitiesByID: [UUID: MessageEntity] = [:]
    private(set) var activeThreadHistory: [Message] = []
    private(set) var isHistoryReady = true
    private(set) var toolResultsByCallID: [String: ToolResult] = [:]
    /// Results published while MCP tools run, before the hidden `.tool`
    /// message lands. Merged over persisted results so the first assistant
    /// card can flip Running → Done without cloning the call onto the live
    /// bubble.
    private var persistedToolResultsByCallID: [String: ToolResult] = [:]
    private var liveToolResultsByCallID: [String: ToolResult] = [:]
    /// Observed by persisted MCP cards. Live upserts must not bump `version`.
    let liveToolResultStore = ChatLiveToolResultStore()
    private var activeConversationID: UUID?
    private(set) var artifactCatalog: ArtifactCatalog = .empty
    /// Total message count from the most recent rebuild. Mirror of the
    /// previously-private `lastRebuildMessageCount`, exposed so `ChatView.body`
    /// can drive its EquatableKey without reading `conversationEntity.messages.count`.
    private(set) var cachedTotalMessageCount: Int = 0

    private var lastRebuildMessageCount = 0
    private var lastRebuildUpdatedAt: Date = .distantPast
    private var updatedAtDebounceTask: Task<Void, Never>?
    private var renderContextBuildTask: Task<Void, Never>?
    private var renderContextDecodeTask: Task<ChatDecodedRenderContext, Never>?
    private var historyDecodeTask: Task<Void, Never>?
    private var activeBuildToken = UUID()

    func rebuildIfNeeded(
        request: ChatRenderCacheRebuildRequest,
        assistantProviderIconID: @escaping @MainActor (String) -> String?,
        isStillCurrent: @escaping @MainActor (UUID, Date) -> Bool,
        onContextApplied: @escaping @MainActor () -> Void,
        onHistoryReady: @escaping @MainActor () -> Void
    ) {
        guard request.allMessages.count != lastRebuildMessageCount
            || request.updatedAt != lastRebuildUpdatedAt else {
            return
        }

        rebuild(
            request: request,
            assistantProviderIconID: assistantProviderIconID,
            isStillCurrent: isStillCurrent,
            onContextApplied: onContextApplied,
            onHistoryReady: onHistoryReady
        )
    }

    func rebuild(
        request: ChatRenderCacheRebuildRequest,
        assistantProviderIconID: @escaping @MainActor (String) -> String?,
        isStillCurrent: @escaping @MainActor (UUID, Date) -> Bool,
        onContextApplied: @escaping @MainActor () -> Void,
        onHistoryReady: @escaping @MainActor () -> Void
    ) {
        cancelBuild()
        activeConversationID = request.conversationID

        let activeMessageCount = request.orderedMessages.count
        let cacheMessageCount = request.allMessages.count
        let messageEntitiesByID = Dictionary(uniqueKeysWithValues: request.orderedMessages.map { ($0.id, $0) })

        if !ChatMessageRenderPipeline.shouldBuildRenderContextAsynchronously(from: request.orderedMessages) {
            let context = ChatMessageRenderPipeline.makeRenderContext(
                from: request.orderedMessages,
                fallbackModelLabel: request.fallbackModelLabel,
                artifactsEnabled: request.artifactsEnabled,
                assistantProviderIconID: assistantProviderIconID
            )
            applyDecodedRenderContext(
                ChatDecodedRenderContext(
                    visibleMessages: context.visibleMessages,
                    historyMessages: context.historyMessages,
                    toolResultsByCallID: context.toolResultsByCallID,
                    artifactCatalog: context.artifactCatalog
                ),
                messageEntitiesByID: context.messageEntitiesByID,
                activeMessageCount: activeMessageCount,
                cacheMessageCount: cacheMessageCount,
                updatedAt: request.updatedAt,
                onContextApplied: onContextApplied
            )
            return
        }

        let snapshots = request.orderedMessages.map(PersistedMessageSnapshot.init)

        // Paint the tail immediately so a switch into a large conversation
        // never shows an empty timeline while the full decode runs. Gated on
        // an EMPTY cache: send-path rebuilds (content already painted) and
        // in-place edits must not regress to a tail-only view. Bookkeeping is
        // deliberately untouched so the full decode still applies over this
        // provisional state.
        if visibleMessages.isEmpty {
            applyProvisionalTailContext(from: snapshots, request: request)
        }

        let buildToken = UUID()
        activeBuildToken = buildToken

        let decodeTask = Task.detached(priority: .userInitiated) {
            ChatMessageRenderPipeline.makeDecodedRenderContext(
                from: snapshots,
                fallbackModelLabel: request.fallbackModelLabel,
                artifactsEnabled: request.artifactsEnabled,
                assistantProviderIconsByID: request.providerIconsByID
            )
        }
        renderContextDecodeTask = decodeTask

        renderContextBuildTask = Task { @MainActor in
            defer {
                if activeBuildToken == buildToken {
                    renderContextBuildTask = nil
                    renderContextDecodeTask = nil
                }
            }

            let decoded = await decodeTask.value
            guard !Task.isCancelled else { return }
            guard activeBuildToken == buildToken else { return }
            guard isStillCurrent(request.conversationID, request.updatedAt) else { return }

            let contextToApply: ChatDecodedRenderContext
            if ChatMessageRenderPipeline.decodedRenderContextDroppedVisibleMessages(
                decoded,
                orderedMessages: request.orderedMessages
            ) {
                let fallbackContext = ChatMessageRenderPipeline.makeRenderContext(
                    from: request.orderedMessages,
                    fallbackModelLabel: request.fallbackModelLabel,
                    artifactsEnabled: request.artifactsEnabled,
                    assistantProviderIconID: assistantProviderIconID
                )
                contextToApply = ChatDecodedRenderContext(
                    visibleMessages: fallbackContext.visibleMessages,
                    historyMessages: fallbackContext.historyMessages,
                    toolResultsByCallID: fallbackContext.toolResultsByCallID,
                    artifactCatalog: fallbackContext.artifactCatalog
                )
            } else {
                contextToApply = decoded
            }

            applyDecodedRenderContext(
                contextToApply,
                messageEntitiesByID: messageEntitiesByID,
                activeMessageCount: activeMessageCount,
                cacheMessageCount: cacheMessageCount,
                updatedAt: request.updatedAt,
                onContextApplied: onContextApplied
            )

            guard contextToApply.historyMessages.isEmpty else {
                onHistoryReady()
                return
            }

            scheduleDecodedHistoryMessages(
                from: snapshots,
                buildToken: buildToken,
                targetConversationID: request.conversationID,
                updatedAt: request.updatedAt,
                isStillCurrent: isStillCurrent,
                onHistoryReady: onHistoryReady
            )
        }
    }

    /// Fast path for the send flow: appends a just-persisted user turn without
    /// re-decoding the conversation (which the async heuristics turn into a
    /// detached full-conversation decode on essentially every real
    /// conversation — the just-sent message stayed invisible until it landed).
    ///
    /// The append itself is unconditional so the row paints immediately.
    /// Bookkeeping advances ONLY when the controller was quiescent and in sync
    /// with the pre-append entity state — then the observer-driven
    /// `rebuildIfNeeded` stays a no-op because this append IS the rebuild's
    /// result for a tail user message (artifacts and tool results are
    /// assistant/tool-role products and cannot change). Returns `false` when a
    /// build/history decode/debounce was in flight or the cache was stale; the
    /// caller must then run a full rebuild to true-up. Every non-exact case
    /// degrades to today's behavior, never worse.
    func appendUserTurn(
        entity: MessageEntity,
        historyMessage: Message,
        renderItem: MessageRenderItem,
        previousUpdatedAt: Date,
        newUpdatedAt: Date,
        totalMessageCount: Int
    ) -> Bool {
        // The debounce check closes a real hole: an edit whose rebuild is
        // still pending would otherwise be suppressed forever once the
        // fast-path bookkeeping moved `lastRebuildUpdatedAt` past it.
        let isExactIncrement = renderContextBuildTask == nil
            && renderContextDecodeTask == nil
            && historyDecodeTask == nil
            && updatedAtDebounceTask == nil
            && isHistoryReady
            && lastRebuildMessageCount == totalMessageCount - 1
            && lastRebuildUpdatedAt == previousUpdatedAt

        visibleMessages.append(renderItem)
        messageEntitiesByID[entity.id] = entity
        activeThreadHistory.append(historyMessage)
        if cachedTotalMessageCount != totalMessageCount {
            cachedTotalMessageCount = totalMessageCount
        }
        version &+= 1

        if isExactIncrement {
            lastRebuildMessageCount = totalMessageCount
            lastRebuildUpdatedAt = newUpdatedAt
        }
        return isExactIncrement
    }

    /// Fast path for editing a persisted user turn: replace that row's
    /// render item, drop everything after it (the regenerate truncate), and
    /// paint immediately. Same bookkeeping contract as `appendUserTurn` —
    /// returns `false` when a true-up rebuild is still required, but the
    /// bubble already shows the new text.
    func applyEditedUserTurn(
        entity: MessageEntity,
        historyMessage: Message,
        renderItem: MessageRenderItem,
        keepMessageIDs: Set<UUID>,
        previousUpdatedAt: Date,
        newUpdatedAt: Date,
        previousTotalMessageCount: Int,
        newTotalMessageCount: Int
    ) -> Bool {
        // A pending debounce was going to rebuild *this* mutation. Cancel
        // it so we can take the exact path when the rest of the cache is
        // already in sync; otherwise the debounce bit would force a full
        // decode of a conversation we just painted.
        updatedAtDebounceTask?.cancel()
        updatedAtDebounceTask = nil

        let isExact = renderContextBuildTask == nil
            && renderContextDecodeTask == nil
            && historyDecodeTask == nil
            && isHistoryReady
            && lastRebuildMessageCount == previousTotalMessageCount
            && lastRebuildUpdatedAt == previousUpdatedAt

        visibleMessages = visibleMessages.compactMap { item in
            if item.id == entity.id { return renderItem }
            return keepMessageIDs.contains(item.id) ? item : nil
        }
        activeThreadHistory = activeThreadHistory.compactMap { message in
            if message.id == entity.id { return historyMessage }
            return keepMessageIDs.contains(message.id) ? message : nil
        }
        messageEntitiesByID = messageEntitiesByID.filter { keepMessageIDs.contains($0.key) }
        messageEntitiesByID[entity.id] = entity

        var remainingToolResults: [String: ToolResult] = [:]
        for message in activeThreadHistory {
            guard let results = message.toolResults else { continue }
            for result in results {
                remainingToolResults[result.toolCallID] = result
            }
        }
        persistedToolResultsByCallID = remainingToolResults
        liveToolResultsByCallID = [:]
        publishMergedToolResults()

        artifactCatalog = artifactCatalog.filtering(toSourceMessageIDs: keepMessageIDs)
        if cachedTotalMessageCount != newTotalMessageCount {
            cachedTotalMessageCount = newTotalMessageCount
        }
        version &+= 1

        if isExact {
            lastRebuildMessageCount = newTotalMessageCount
            lastRebuildUpdatedAt = newUpdatedAt
        }
        return isExact
    }

    func scheduleDebouncedRebuild(
        after delay: Duration,
        action: @escaping @MainActor () -> Void
    ) {
        updatedAtDebounceTask?.cancel()
        updatedAtDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
            updatedAtDebounceTask = nil
        }
    }

    func cancelPendingWork() {
        updatedAtDebounceTask?.cancel()
        updatedAtDebounceTask = nil
        cancelBuild()
    }

    func cancelBuild() {
        activeBuildToken = UUID()
        renderContextBuildTask?.cancel()
        renderContextBuildTask = nil
        renderContextDecodeTask?.cancel()
        renderContextDecodeTask = nil
        historyDecodeTask?.cancel()
        historyDecodeTask = nil
    }

    func clearForConversationSwitch() {
        cancelPendingWork()
        visibleMessages = []
        messageEntitiesByID = [:]
        activeThreadHistory = []
        isHistoryReady = true
        persistedToolResultsByCallID = [:]
        liveToolResultsByCallID = [:]
        liveToolResultStore.clear()
        liveToolResultStore.setSuppressIdleStreamingPlaceholder(false)
        activeConversationID = nil
        toolResultsByCallID = [:]
        artifactCatalog = .empty
        cachedTotalMessageCount = 0
        version &+= 1
        lastRebuildMessageCount = 0
        lastRebuildUpdatedAt = .distantPast
    }

    func singleThreadContext() -> ChatThreadRenderContext {
        ChatThreadRenderContext(
            visibleMessages: visibleMessages,
            historyMessages: activeThreadHistory,
            messageEntitiesByID: messageEntitiesByID,
            // Persisted snapshot only. Live results ride `liveToolResultStore`
            // so ChatView / the table epoch do not rebuild on every tool body.
            toolResultsByCallID: persistedToolResultsByCallID,
            artifactCatalog: artifactCatalog
        )
    }

    func upsertLiveToolResult(_ result: ToolResult, conversationID: UUID) {
        guard activeConversationID == conversationID else { return }
        liveToolResultsByCallID[result.toolCallID] = result
        publishMergedToolResults()
    }

    private func replacePersistedToolResults(_ results: [String: ToolResult]) {
        persistedToolResultsByCallID = results
        if !liveToolResultsByCallID.isEmpty {
            liveToolResultsByCallID = liveToolResultsByCallID.filter { callID, _ in
                persistedToolResultsByCallID[callID] == nil
            }
        }
        publishMergedToolResults()
    }

    private func publishMergedToolResults() {
        if liveToolResultsByCallID.isEmpty {
            toolResultsByCallID = persistedToolResultsByCallID
        } else {
            toolResultsByCallID = persistedToolResultsByCallID.merging(liveToolResultsByCallID) { _, live in
                live
            }
        }
        liveToolResultStore.replaceAll(liveToolResultsByCallID)
    }

    /// Synchronous tail-only decode for the first paint after a conversation
    /// switch. Sets ONLY the display-facing properties: `lastRebuild*` stay
    /// untouched (the full decode must still run and apply), `isHistoryReady`
    /// keeps gating the token gauge, and `artifactCatalog` is left alone —
    /// tail-local artifact version numbers would be wrong, and the full apply
    /// corrects the chips moments later.
    private func applyProvisionalTailContext(
        from snapshots: [PersistedMessageSnapshot],
        request: ChatRenderCacheRebuildRequest
    ) {
        let tail = ChatRenderProvisionalTailPolicy.tailSlice(of: snapshots)
        guard !tail.isEmpty else { return }

        let context = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: tail,
            fallbackModelLabel: request.fallbackModelLabel,
            artifactsEnabled: request.artifactsEnabled,
            assistantProviderIconsByID: request.providerIconsByID
        )
        guard !context.visibleMessages.isEmpty else { return }

        let tailIDs = Set(tail.map(\.id))
        visibleMessages = context.visibleMessages
        messageEntitiesByID = Dictionary(
            uniqueKeysWithValues: request.orderedMessages
                .filter { tailIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )
        replacePersistedToolResults(context.toolResultsByCallID)
        version &+= 1
    }

    private func applyDecodedRenderContext(
        _ context: ChatDecodedRenderContext,
        messageEntitiesByID: [UUID: MessageEntity],
        activeMessageCount: Int,
        cacheMessageCount: Int,
        updatedAt: Date,
        onContextApplied: () -> Void
    ) {
        visibleMessages = context.visibleMessages
        self.messageEntitiesByID = messageEntitiesByID
        activeThreadHistory = context.historyMessages
        isHistoryReady = !context.historyMessages.isEmpty || activeMessageCount == 0
        replacePersistedToolResults(context.toolResultsByCallID)
        artifactCatalog = context.artifactCatalog
        if cachedTotalMessageCount != cacheMessageCount {
            cachedTotalMessageCount = cacheMessageCount
        }
        version &+= 1
        lastRebuildMessageCount = cacheMessageCount
        lastRebuildUpdatedAt = updatedAt
        onContextApplied()
    }

    private func scheduleDecodedHistoryMessages(
        from snapshots: [PersistedMessageSnapshot],
        buildToken: UUID,
        targetConversationID: UUID,
        updatedAt: Date,
        isStillCurrent: @escaping @MainActor (UUID, Date) -> Bool,
        onHistoryReady: @escaping @MainActor () -> Void
    ) {
        historyDecodeTask?.cancel()
        historyDecodeTask = Task { @MainActor in
            let history = await Task.detached(priority: .utility) {
                ChatMessageRenderPipeline.decodeHistoryMessages(from: snapshots)
            }.value

            guard !Task.isCancelled else { return }
            guard activeBuildToken == buildToken else { return }
            guard isStillCurrent(targetConversationID, updatedAt) else { return }

            activeThreadHistory = history
            isHistoryReady = true
            historyDecodeTask = nil
            onHistoryReady()
        }
    }
}
