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

    func resolvedClaudeManagedAgentOptions(
        for providerID: String,
        threadControls: GenerationControls?
    ) -> [ClaudeManagedAgentDescriptor] {
        let resolvedControls = resolvedClaudeManagedControls(for: providerID, threadControls: threadControls)
        var agents = providerID == conversationEntity.providerID ? claudeManagedAvailableAgents : []

        if let selectedAgentID = resolvedControls.claudeManagedAgentID,
           !agents.contains(where: { $0.id == selectedAgentID }) {
            agents.insert(
                ClaudeManagedAgentDescriptor(
                    id: selectedAgentID,
                    name: resolvedControls.claudeManagedAgentDisplayName ?? selectedAgentID,
                    modelID: resolvedControls.claudeManagedAgentModelID,
                    modelDisplayName: resolvedControls.claudeManagedAgentModelDisplayName
                ),
                at: 0
            )
        }

        return agents
    }

    func resolvedClaudeManagedAgentDisplayName(
        for providerID: String,
        threadModelID: String,
        threadControls: GenerationControls?
    ) -> String {
        let resolvedControls = resolvedClaudeManagedControls(for: providerID, threadControls: threadControls)
        if let selectedAgentID = resolvedControls.claudeManagedAgentID,
           let descriptor = resolvedClaudeManagedAgentOptions(for: providerID, threadControls: threadControls)
            .first(where: { $0.id == selectedAgentID }) {
            return descriptor.name
        }

        return ClaudeManagedAgentRuntime.resolvedDisplayName(
            threadModelID: threadModelID,
            controls: resolvedControls
        )
    }

    func resolvedClaudeManagedEnvironmentDisplayName(
        for providerID: String,
        threadControls: GenerationControls?
    ) -> String? {
        let resolvedControls = resolvedClaudeManagedControls(for: providerID, threadControls: threadControls)
        if let selectedEnvironmentID = resolvedControls.claudeManagedEnvironmentID,
           providerID == conversationEntity.providerID,
           let descriptor = claudeManagedAvailableEnvironments.first(where: { $0.id == selectedEnvironmentID }) {
            return descriptor.name
        }

        return resolvedControls.claudeManagedEnvironmentDisplayName ?? resolvedControls.claudeManagedEnvironmentID
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
