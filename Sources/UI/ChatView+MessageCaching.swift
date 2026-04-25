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
        renderCache.rebuildIfNeeded(
            request: makeRenderCacheRebuildRequest(),
            modelNameForThread: renderCacheModelName,
            assistantProviderIconID: renderCacheProviderIconID,
            isStillCurrent: isRenderCacheRequestStillCurrent,
            onContextApplied: syncArtifactSelectionForActiveThread,
            onHistoryReady: { refreshContextUsageEstimate(debounced: false) }
        )
    }

    func rebuildMessageCaches() {
        renderCache.rebuild(
            request: makeRenderCacheRebuildRequest(),
            modelNameForThread: renderCacheModelName,
            assistantProviderIconID: renderCacheProviderIconID,
            isStillCurrent: isRenderCacheRequestStillCurrent,
            onContextApplied: syncArtifactSelectionForActiveThread,
            onHistoryReady: { refreshContextUsageEstimate(debounced: false) }
        )
    }

    func cancelRenderContextBuild() {
        renderCache.cancelBuild()
    }

    func syncArtifactSelectionForActiveThread() {
        guard let threadID = activeModelThread?.id else { return }

        let catalog = activeModelThread?.id == activeThreadID
            ? renderCache.artifactCatalog
            : threadRenderContext(threadID: threadID).artifactCatalog
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
        guard renderCache.selectLatestArtifact(
            from: message,
            threadID: threadID,
            selectedArtifactIDByThreadID: &selectedArtifactIDByThreadID,
            selectedArtifactVersionByThreadID: &selectedArtifactVersionByThreadID
        ) else {
            return
        }

        isArtifactPaneVisible = true
    }

    private func makeRenderCacheRebuildRequest() -> ChatRenderCacheRebuildRequest {
        let threadID = activeModelThread?.id
        return ChatRenderCacheRebuildRequest(
            conversationID: conversationEntity.id,
            activeThreadID: threadID,
            allMessages: conversationEntity.messages,
            orderedMessages: orderedConversationMessages(threadID: threadID),
            selectedThreads: selectedModelThreads,
            updatedAt: conversationEntity.updatedAt,
            fallbackModelLabel: currentModelName,
            providerIconsByID: Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.resolvedProviderIconID) })
        )
    }

    private func isRenderCacheRequestStillCurrent(
        conversationID: UUID,
        activeThreadID: UUID?,
        updatedAt: Date
    ) -> Bool {
        conversationEntity.id == conversationID
            && activeModelThread?.id == activeThreadID
            && conversationEntity.updatedAt == updatedAt
    }

    private func renderCacheModelName(for thread: ConversationModelThreadEntity) -> String {
        modelName(id: thread.modelID, providerID: thread.providerID)
    }

    private func renderCacheProviderIconID(for providerID: String) -> String? {
        providerIconID(for: providerID)
    }
}
