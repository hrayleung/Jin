import SwiftUI
import SwiftData

// MARK: - Claude Managed Agent Session Persistence

extension ChatView {

    func injectClaudeManagedAgentSessionPersistence(into controls: inout GenerationControls, from thread: ConversationModelThreadEntity) {
        guard providerType(forProviderID: thread.providerID) == .claudeManagedAgents else {
            controls.clearClaudeManagedAgentSessionState()
            return
        }

        let storedControls = storedGenerationControls(for: thread) ?? GenerationControls()
        controls.claudeManagedSessionID = storedControls.claudeManagedSessionID
        controls.claudeManagedSessionModelID = storedControls.claudeManagedSessionModelID
        controls.claudeManagedPendingCustomToolResults = storedControls.claudeManagedPendingCustomToolResults
    }

    func persistClaudeManagedAgentSessionID(_ sessionID: String?, forLocalThreadID threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .claudeManagedAgents else { return }

        mutateStoredGenerationControls(for: thread) { storedControls in
            storedControls.claudeManagedSessionID = sessionID
            storedControls.claudeManagedSessionModelID = nil
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
