import Foundation
import SwiftUI

struct ChatRenderCacheRebuildRequest {
    let conversationID: UUID
    let activeThreadID: UUID?
    let allMessages: [MessageEntity]
    let orderedMessages: [MessageEntity]
    let selectedThreads: [ConversationModelThreadEntity]
    let updatedAt: Date
    let fallbackModelLabel: String
    let providerIconsByID: [String: String?]
}

@MainActor
final class ChatRenderCacheController: ObservableObject {
    @Published private(set) var visibleMessages: [MessageRenderItem] = []
    @Published private(set) var version: Int = 0
    @Published private(set) var messageEntitiesByID: [UUID: MessageEntity] = [:]
    @Published private(set) var activeThreadHistory: [Message] = []
    @Published private(set) var isHistoryReady = true
    @Published private(set) var toolResultsByCallID: [String: ToolResult] = [:]
    @Published private(set) var artifactCatalog: ArtifactCatalog = .empty
    @Published private(set) var contextsByThreadID: [UUID: ChatThreadRenderContext] = [:]

    private var lastRebuildMessageCount = 0
    private var lastRebuildUpdatedAt: Date = .distantPast
    private var updatedAtDebounceTask: Task<Void, Never>?
    private var renderContextBuildTask: Task<Void, Never>?
    private var renderContextDecodeTask: Task<ChatDecodedRenderContext, Never>?
    private var historyDecodeTask: Task<Void, Never>?
    private var activeBuildToken = UUID()

    deinit {
        updatedAtDebounceTask?.cancel()
        renderContextBuildTask?.cancel()
        renderContextDecodeTask?.cancel()
        historyDecodeTask?.cancel()
    }

    func rebuildIfNeeded(
        request: ChatRenderCacheRebuildRequest,
        modelNameForThread: @escaping @MainActor (ConversationModelThreadEntity) -> String,
        assistantProviderIconID: @escaping @MainActor (String) -> String?,
        isStillCurrent: @escaping @MainActor (UUID, UUID?, Date) -> Bool,
        onContextApplied: @escaping @MainActor () -> Void,
        onHistoryReady: @escaping @MainActor () -> Void
    ) {
        guard request.allMessages.count != lastRebuildMessageCount
            || request.updatedAt != lastRebuildUpdatedAt else {
            return
        }

        rebuild(
            request: request,
            modelNameForThread: modelNameForThread,
            assistantProviderIconID: assistantProviderIconID,
            isStillCurrent: isStillCurrent,
            onContextApplied: onContextApplied,
            onHistoryReady: onHistoryReady
        )
    }

    func rebuild(
        request: ChatRenderCacheRebuildRequest,
        modelNameForThread: @escaping @MainActor (ConversationModelThreadEntity) -> String,
        assistantProviderIconID: @escaping @MainActor (String) -> String?,
        isStillCurrent: @escaping @MainActor (UUID, UUID?, Date) -> Bool,
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
                allMessages: request.allMessages,
                selectedThreads: request.selectedThreads,
                activeMessageCount: activeMessageCount,
                cacheMessageCount: cacheMessageCount,
                updatedAt: request.updatedAt,
                activeThreadID: request.activeThreadID,
                modelNameForThread: modelNameForThread,
                assistantProviderIconID: assistantProviderIconID,
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
            guard isStillCurrent(request.conversationID, request.activeThreadID, request.updatedAt) else { return }

            let contextToApply: ChatDecodedRenderContext
            if ChatMessageRenderPipeline.decodedRenderContextDroppedVisibleMessages(
                decoded,
                orderedMessages: request.orderedMessages
            ) {
                let fallbackContext = ChatMessageRenderPipeline.makeRenderContext(
                    from: request.orderedMessages,
                    fallbackModelLabel: request.fallbackModelLabel,
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
                allMessages: request.allMessages,
                selectedThreads: request.selectedThreads,
                activeMessageCount: activeMessageCount,
                cacheMessageCount: cacheMessageCount,
                updatedAt: request.updatedAt,
                activeThreadID: request.activeThreadID,
                modelNameForThread: modelNameForThread,
                assistantProviderIconID: assistantProviderIconID,
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
                targetThreadID: request.activeThreadID,
                updatedAt: request.updatedAt,
                isStillCurrent: isStillCurrent,
                onHistoryReady: onHistoryReady
            )
        }
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
        contextsByThreadID = [:]
        version &+= 1
        lastRebuildMessageCount = 0
        lastRebuildUpdatedAt = .distantPast
    }

    func singleThreadContext(activeThreadID: UUID?) -> ChatThreadRenderContext {
        if let activeThreadID, let cached = contextsByThreadID[activeThreadID] {
            return cached
        }

        return ChatThreadRenderContext(
            visibleMessages: visibleMessages,
            historyMessages: activeThreadHistory,
            messageEntitiesByID: messageEntitiesByID,
            toolResultsByCallID: toolResultsByCallID,
            artifactCatalog: artifactCatalog
        )
    }

    func threadContext(
        threadID: UUID,
        allMessages: [MessageEntity],
        sortedThreads: [ConversationModelThreadEntity],
        currentModelName: String,
        modelNameForThread: (ConversationModelThreadEntity) -> String,
        assistantProviderIconID: (String) -> String?
    ) -> ChatThreadRenderContext {
        if let cached = contextsByThreadID[threadID] {
            return cached
        }

        let fallbackModelLabel = sortedThreads
            .first(where: { $0.id == threadID })
            .map(modelNameForThread)
            ?? currentModelName

        return ChatRenderContextBatchBuilder.makeContext(
            allMessages: allMessages,
            threadID: threadID,
            fallbackModelLabel: fallbackModelLabel,
            assistantProviderIconID: assistantProviderIconID
        )
    }

    func selectLatestArtifact(
        from message: Message,
        threadID: UUID,
        selectedArtifactIDByThreadID: inout [UUID: String],
        selectedArtifactVersionByThreadID: inout [UUID: Int]
    ) -> Bool {
        let artifacts = message.content.compactMap { part -> [ParsedArtifact]? in
            guard case .text(let text) = part else { return nil }
            return ArtifactMarkupParser.parse(text).artifacts
        }.flatMap { $0 }

        guard let latest = artifacts.last else { return false }

        if let resolvedVersion = artifactCatalog.latestVersion(for: latest.artifactID) {
            selectedArtifactIDByThreadID[threadID] = resolvedVersion.artifactID
            selectedArtifactVersionByThreadID[threadID] = resolvedVersion.version
        } else {
            selectedArtifactIDByThreadID[threadID] = latest.artifactID
        }

        return true
    }

    private func applyDecodedRenderContext(
        _ context: ChatDecodedRenderContext,
        messageEntitiesByID: [UUID: MessageEntity],
        allMessages: [MessageEntity],
        selectedThreads: [ConversationModelThreadEntity],
        activeMessageCount: Int,
        cacheMessageCount: Int,
        updatedAt: Date,
        activeThreadID: UUID?,
        modelNameForThread: (ConversationModelThreadEntity) -> String,
        assistantProviderIconID: (String) -> String?,
        onContextApplied: () -> Void
    ) {
        let activeContext = ChatRenderContextBatchBuilder.makeFallbackContext(
            visibleMessages: context.visibleMessages,
            historyMessages: context.historyMessages,
            messageEntitiesByID: messageEntitiesByID,
            toolResultsByCallID: context.toolResultsByCallID,
            artifactCatalog: context.artifactCatalog
        )
        let batch = ChatRenderContextBatchBuilder.makeBatch(
            allMessages: allMessages,
            activeThreadID: activeThreadID,
            selectedThreads: selectedThreads,
            activeContext: activeContext,
            modelNameForThread: modelNameForThread,
            assistantProviderIconID: assistantProviderIconID
        )
        applyRenderContextBatch(
            batch,
            activeMessageCount: activeMessageCount,
            cacheMessageCount: cacheMessageCount,
            updatedAt: updatedAt
        )
        onContextApplied()
    }

    private func applyRenderContextBatch(
        _ batch: ChatRenderContextBatch,
        activeMessageCount: Int,
        cacheMessageCount: Int,
        updatedAt: Date
    ) {
        let activeContext = batch.activeContext
        visibleMessages = activeContext.visibleMessages
        messageEntitiesByID = activeContext.messageEntitiesByID
        activeThreadHistory = activeContext.historyMessages
        isHistoryReady = !activeContext.historyMessages.isEmpty || activeMessageCount == 0
        toolResultsByCallID = activeContext.toolResultsByCallID
        artifactCatalog = activeContext.artifactCatalog
        contextsByThreadID = batch.contextsByThreadID
        version &+= 1
        lastRebuildMessageCount = cacheMessageCount
        lastRebuildUpdatedAt = updatedAt
    }

    private func scheduleDecodedHistoryMessages(
        from snapshots: [PersistedMessageSnapshot],
        buildToken: UUID,
        targetConversationID: UUID,
        targetThreadID: UUID?,
        updatedAt: Date,
        isStillCurrent: @escaping @MainActor (UUID, UUID?, Date) -> Bool,
        onHistoryReady: @escaping @MainActor () -> Void
    ) {
        historyDecodeTask?.cancel()
        historyDecodeTask = Task { @MainActor in
            let history = await Task.detached(priority: .utility) {
                ChatMessageRenderPipeline.decodeHistoryMessages(from: snapshots)
            }.value

            guard !Task.isCancelled else { return }
            guard activeBuildToken == buildToken else { return }
            guard isStillCurrent(targetConversationID, targetThreadID, updatedAt) else { return }

            applyDecodedHistoryMessages(history, activeThreadID: targetThreadID)
            historyDecodeTask = nil
            onHistoryReady()
        }
    }

    private func applyDecodedHistoryMessages(_ historyMessages: [Message], activeThreadID: UUID?) {
        activeThreadHistory = historyMessages
        isHistoryReady = true
        if let activeThreadID {
            let visibleMessages = contextsByThreadID[activeThreadID]?.visibleMessages ?? self.visibleMessages
            let messageEntitiesByID = contextsByThreadID[activeThreadID]?.messageEntitiesByID ?? self.messageEntitiesByID
            let toolResultsByCallID = contextsByThreadID[activeThreadID]?.toolResultsByCallID ?? self.toolResultsByCallID
            let artifactCatalog = contextsByThreadID[activeThreadID]?.artifactCatalog ?? self.artifactCatalog

            contextsByThreadID[activeThreadID] = ChatThreadRenderContext(
                visibleMessages: visibleMessages,
                historyMessages: historyMessages,
                messageEntitiesByID: messageEntitiesByID,
                toolResultsByCallID: toolResultsByCallID,
                artifactCatalog: artifactCatalog
            )
        }
    }
}
