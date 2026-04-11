import SwiftUI
import SwiftData

// MARK: - Claude Managed Agent Session Persistence

extension ChatView {
    func resolvedClaudeManagedControls(
        for providerID: String,
        threadControls: GenerationControls?
    ) -> GenerationControls {
        var controls = threadControls ?? GenerationControls()
        providers.first(where: { $0.id == providerID })?.applyClaudeManagedDefaults(into: &controls)
        return controls
    }

    func defaultClaudeManagedAgentControls(for providerID: String) -> GenerationControls {
        resolvedClaudeManagedControls(for: providerID, threadControls: nil)
    }

    func managedAgentSyntheticModelID(
        providerID: String,
        controls: GenerationControls
    ) -> String {
        ClaudeManagedAgentRuntime.syntheticThreadModelID(
            providerID: providerID,
            agentID: controls.claudeManagedAgentID,
            environmentID: controls.claudeManagedEnvironmentID
        )
    }

    func injectClaudeManagedAgentSessionPersistence(into controls: inout GenerationControls, from thread: ConversationModelThreadEntity) {
        guard providerType(forProviderID: thread.providerID) == .claudeManagedAgents else {
            controls.clearClaudeManagedAgentSessionState()
            return
        }

        let storedControls = storedGenerationControls(for: thread) ?? GenerationControls()
        providers.first(where: { $0.id == thread.providerID })?.applyClaudeManagedDefaults(into: &controls)
        controls.claudeManagedSessionID = storedControls.claudeManagedSessionID
        controls.claudeManagedSessionModelID = storedControls.claudeManagedSessionModelID
        controls.claudeManagedPendingCustomToolResults = storedControls.claudeManagedPendingCustomToolResults
    }

    func persistClaudeManagedAgentSessionState(_ state: ClaudeManagedAgentSessionState, forLocalThreadID threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .claudeManagedAgents else { return }

        mutateStoredGenerationControls(for: thread) { storedControls in
            storedControls.claudeManagedSessionID = state.remoteSessionID
            storedControls.claudeManagedSessionModelID = state.remoteModelID
        }
    }

    func persistClaudeManagedPendingCustomToolResults(
        _ results: [ClaudeManagedAgentPendingToolResult],
        forLocalThreadID threadID: UUID
    ) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .claudeManagedAgents else { return }

        mutateStoredGenerationControls(for: thread) { storedControls in
            storedControls.claudeManagedPendingCustomToolResults = results
        }
    }

    func clearClaudeManagedAgentSessionPersistence(for thread: ConversationModelThreadEntity) {
        guard providerType(forProviderID: thread.providerID) == .claudeManagedAgents else { return }
        mutateStoredGenerationControls(for: thread) { storedControls in
            storedControls.clearClaudeManagedAgentSessionState()
        }
    }

    func invalidateClaudeManagedAgentSessionPersistence(forThreadID threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .claudeManagedAgents else { return }
        clearClaudeManagedAgentSessionPersistence(for: thread)
    }

    func recordClaudeManagedAgentHistoryMutation(forThreadID threadID: UUID, removedMessages: [MessageEntity]) {
        guard !removedMessages.isEmpty else { return }
        invalidateClaudeManagedAgentSessionPersistence(forThreadID: threadID)
    }
}
