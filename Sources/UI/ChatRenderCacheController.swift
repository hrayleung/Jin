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
            toolResultsByCallID: toolResultsByCallID,
            artifactCatalog: artifactCatalog
        )
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
        toolResultsByCallID = context.toolResultsByCallID
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
