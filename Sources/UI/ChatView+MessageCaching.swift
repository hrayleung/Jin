import SwiftUI
import SwiftData

// MARK: - Message Caching & Artifact Sync

extension ChatView {

    func orderedConversationMessages() -> [MessageEntity] {
        ChatMessageRenderPipeline.orderedMessages(from: conversationEntity.messages)
    }

    func rebuildMessageCachesIfNeeded() {
        renderCache.rebuildIfNeeded(
            request: makeRenderCacheRebuildRequest(),
            assistantProviderIconID: renderCacheProviderIconID,
            isStillCurrent: isRenderCacheRequestStillCurrent,
            onContextApplied: syncArtifactSelection,
            onHistoryReady: { refreshContextUsageEstimate(debounced: false) }
        )
    }

    func rebuildMessageCaches() {
        renderCache.rebuild(
            request: makeRenderCacheRebuildRequest(),
            assistantProviderIconID: renderCacheProviderIconID,
            isStillCurrent: isRenderCacheRequestStillCurrent,
            onContextApplied: syncArtifactSelection,
            onHistoryReady: { refreshContextUsageEstimate(debounced: false) }
        )
    }

    func cancelRenderContextBuild() {
        renderCache.cancelBuild()
    }

    func syncArtifactSelection() {
        let catalog = renderCache.artifactCatalog
        guard !catalog.isEmpty else {
            selectedArtifactID = nil
            selectedArtifactVersion = nil
            return
        }

        let selection = ArtifactWorkspaceSupport.selectionAfterSync(
            in: catalog,
            selectedArtifactID: selectedArtifactID,
            selectedArtifactVersion: selectedArtifactVersion
        )

        if selection.artifactID == selectedArtifactID,
           selection.version == selectedArtifactVersion {
            return
        }

        selectedArtifactID = selection.artifactID
        selectedArtifactVersion = selection.version
    }

    func openArtifact(_ artifact: RenderedArtifactVersion) {
        selectedArtifactID = artifact.artifactID
        selectedArtifactVersion = artifact.version
        isArtifactPaneVisible = true
    }

    func autoOpenLatestArtifactIfNeeded(from message: Message) {
        guard let selection = ArtifactWorkspaceSupport.latestArtifactSelection(
            from: message,
            in: renderCache.artifactCatalog
        ) else {
            return
        }

        selectedArtifactID = selection.artifactID
        if let version = selection.version {
            selectedArtifactVersion = version
        }
        isArtifactPaneVisible = true
    }

    private func makeRenderCacheRebuildRequest() -> ChatRenderCacheRebuildRequest {
        ChatRenderCacheRebuildRequest(
            conversationID: conversationEntity.id,
            allMessages: conversationEntity.messages,
            orderedMessages: orderedConversationMessages(),
            updatedAt: conversationEntity.updatedAt,
            fallbackModelLabel: currentModelName,
            providerIconsByID: Dictionary(
                providers.map { ($0.id, $0.resolvedProviderIconID) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    private func isRenderCacheRequestStillCurrent(
        conversationID: UUID,
        updatedAt: Date
    ) -> Bool {
        conversationEntity.id == conversationID
            && conversationEntity.updatedAt == updatedAt
    }

    private func renderCacheProviderIconID(for providerID: String) -> String? {
        providerIconID(for: providerID)
    }
}
