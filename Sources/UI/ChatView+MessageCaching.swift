import SwiftUI
import SwiftData

// MARK: - Message Caching & Artifact Sync

extension ChatView {

    func orderedConversationMessages(threadID: UUID? = nil) -> [MessageEntity] {
        ChatMessageRenderPipeline.orderedMessages(
            from: conversationEntity.messages,
            threadID: threadID
        )
    }

    func rebuildMessageCachesIfNeeded() {
        guard conversationEntity.messages.count != lastCacheRebuildMessageCount
            || conversationEntity.updatedAt != lastCacheRebuildUpdatedAt else {
            return
        }

        rebuildMessageCaches()
    }

    func rebuildMessageCaches() {
        let threadID = activeModelThread?.id
        let ordered = orderedConversationMessages(threadID: threadID)
        let historyMessages = decodedHistoryMessages(from: ordered)
        let targetUpdatedAt = conversationEntity.updatedAt
        let fallbackModelLabel = currentModelName

        cancelRenderContextBuild()

        let messageEntitiesByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        if ordered.count < Self.asyncCacheBuildMessageThreshold {
            let context = ChatMessageRenderPipeline.makeRenderContext(
                from: ordered,
                fallbackModelLabel: fallbackModelLabel,
                assistantProviderIconID: { providerID in
                    providerIconID(for: providerID)
                }
            )
            applyDecodedRenderContext(
                ChatDecodedRenderContext(
                    visibleMessages: context.visibleMessages,
                    toolResultsByCallID: context.toolResultsByCallID,
                    artifactCatalog: context.artifactCatalog
                ),
                historyMessages: historyMessages,
                messageEntitiesByID: context.messageEntitiesByID,
                messageCount: ordered.count,
                updatedAt: targetUpdatedAt
            )
            return
        }

        let providerIconsByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.resolvedProviderIconID) })
        let snapshots = ordered.map(PersistedMessageSnapshot.init)
        let targetConversationID = conversationEntity.id
        let targetThreadID = threadID
        let messageCount = ordered.count
        let buildToken = UUID()
        activeRenderContextBuildToken = buildToken

        let decodeTask = Task.detached(priority: .userInitiated) {
            ChatMessageRenderPipeline.makeDecodedRenderContext(
                from: snapshots,
                fallbackModelLabel: fallbackModelLabel,
                assistantProviderIconsByID: providerIconsByID
            )
        }
        renderContextDecodeTask = decodeTask

        renderContextBuildTask = Task { @MainActor in
            defer {
                if activeRenderContextBuildToken == buildToken {
                    renderContextBuildTask = nil
                    renderContextDecodeTask = nil
                }
            }

            let decoded = await decodeTask.value
            guard !Task.isCancelled else { return }
            guard activeRenderContextBuildToken == buildToken else { return }
            guard conversationEntity.id == targetConversationID else { return }
            guard activeModelThread?.id == targetThreadID else { return }
            guard conversationEntity.updatedAt == targetUpdatedAt else { return }

            applyDecodedRenderContext(
                decoded,
                historyMessages: historyMessages,
                messageEntitiesByID: messageEntitiesByID,
                messageCount: messageCount,
                updatedAt: targetUpdatedAt
            )
        }
    }

    func cancelRenderContextBuild() {
        activeRenderContextBuildToken = UUID()
        renderContextBuildTask?.cancel()
        renderContextBuildTask = nil
        renderContextDecodeTask?.cancel()
        renderContextDecodeTask = nil
    }

    func applyDecodedRenderContext(
        _ context: ChatDecodedRenderContext,
        historyMessages: [Message],
        messageEntitiesByID: [UUID: MessageEntity],
        messageCount: Int,
        updatedAt: Date
    ) {
        cachedVisibleMessages = context.visibleMessages
        cachedMessageEntitiesByID = messageEntitiesByID
        cachedActiveThreadHistory = historyMessages
        cachedToolResultsByCallID = context.toolResultsByCallID
        cachedArtifactCatalog = context.artifactCatalog
        cachedMessagesVersion &+= 1
        lastCacheRebuildMessageCount = messageCount
        lastCacheRebuildUpdatedAt = updatedAt
        syncArtifactSelectionForActiveThread()
    }

    func decodedHistoryMessages(from messageEntities: [MessageEntity]) -> [Message] {
        let decoder = JSONDecoder()
        return messageEntities
            .map(PersistedMessageSnapshot.init)
            .compactMap { $0.toDomain(using: decoder) }
    }

    func syncArtifactSelectionForActiveThread() {
        guard let threadID = activeModelThread?.id else { return }

        let catalog = activeModelThread?.id == activeThreadID ? cachedArtifactCatalog : threadRenderContext(threadID: threadID).artifactCatalog
        guard !catalog.isEmpty else {
            selectedArtifactIDByThreadID[threadID] = nil
            selectedArtifactVersionByThreadID[threadID] = nil
            return
        }

        let selectedArtifactID = selectedArtifactIDByThreadID[threadID]
        let selectedVersion = selectedArtifactVersionByThreadID[threadID]

        if let selectedArtifactID,
           catalog.version(artifactID: selectedArtifactID, version: selectedVersion) != nil {
            return
        }

        if let latest = catalog.latestVersion {
            selectedArtifactIDByThreadID[threadID] = latest.artifactID
            selectedArtifactVersionByThreadID[threadID] = latest.version
        }
    }

    func openArtifact(_ artifact: RenderedArtifactVersion, threadID: UUID?) {
        let resolvedThreadID = threadID ?? activeModelThread?.id
        if let resolvedThreadID, activeModelThread?.id != resolvedThreadID {
            activateThread(by: resolvedThreadID)
        }

        if let resolvedThreadID {
            selectedArtifactIDByThreadID[resolvedThreadID] = artifact.artifactID
            selectedArtifactVersionByThreadID[resolvedThreadID] = artifact.version
        }

        isArtifactPaneVisible = true
    }

    func autoOpenLatestArtifactIfNeeded(from message: Message, threadID: UUID) {
        guard activeModelThread?.id == threadID else { return }

        let artifacts = message.content.compactMap { part -> [ParsedArtifact]? in
            guard case .text(let text) = part else { return nil }
            return ArtifactMarkupParser.parse(text).artifacts
        }.flatMap { $0 }

        guard let latest = artifacts.last else { return }

        let catalog = cachedArtifactCatalog
        let resolvedVersion = catalog.latestVersion(for: latest.artifactID)
        if let resolvedVersion {
            selectedArtifactIDByThreadID[threadID] = resolvedVersion.artifactID
            selectedArtifactVersionByThreadID[threadID] = resolvedVersion.version
        } else {
            selectedArtifactIDByThreadID[threadID] = latest.artifactID
        }

        isArtifactPaneVisible = true
    }
}
