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
        var agents = providerID == activeProviderID ? claudeManagedAvailableAgents : []

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
        modelID: String,
        controls: GenerationControls?
    ) -> String {
        let resolvedControls = resolvedClaudeManagedControls(for: providerID, threadControls: controls)
        if let selectedAgentID = resolvedControls.claudeManagedAgentID,
           let descriptor = resolvedClaudeManagedAgentOptions(for: providerID, threadControls: controls)
            .first(where: { $0.id == selectedAgentID }) {
            return descriptor.name
        }

        return ClaudeManagedAgentRuntime.resolvedDisplayName(
            threadModelID: modelID,
            controls: resolvedControls
        )
    }

    func resolvedClaudeManagedEnvironmentDisplayName(
        for providerID: String,
        threadControls: GenerationControls?
    ) -> String? {
        let resolvedControls = resolvedClaudeManagedControls(for: providerID, threadControls: threadControls)
        if let selectedEnvironmentID = resolvedControls.claudeManagedEnvironmentID,
           providerID == activeProviderID,
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

    func injectClaudeManagedAgentSessionPersistence(into controls: inout GenerationControls) {
        guard providerType == .claudeManagedAgents else {
            controls.clearClaudeManagedAgentSessionState()
            return
        }

        let storedControls = storedGenerationControls() ?? GenerationControls()
        currentProvider?.applyClaudeManagedDefaults(into: &controls)
        controls.claudeManagedSessionID = storedControls.claudeManagedSessionID
        controls.claudeManagedSessionModelID = storedControls.claudeManagedSessionModelID
        controls.claudeManagedPendingCustomToolResults = storedControls.claudeManagedPendingCustomToolResults
    }

    func persistClaudeManagedAgentSessionState(_ state: ClaudeManagedAgentSessionState) {
        guard providerType == .claudeManagedAgents else { return }
        mutateStoredGenerationControls { storedControls in
            storedControls.claudeManagedSessionID = state.remoteSessionID
            storedControls.claudeManagedSessionModelID = state.remoteModelID
        }
    }

    func persistClaudeManagedPendingCustomToolResults(
        _ results: [ClaudeManagedAgentPendingToolResult]
    ) {
        guard providerType == .claudeManagedAgents else { return }
        mutateStoredGenerationControls { storedControls in
            storedControls.claudeManagedPendingCustomToolResults = results
        }
    }

    func clearClaudeManagedAgentSessionPersistence(for conversation: ConversationEntity) {
        guard providerType(forProviderID: conversation.providerID) == .claudeManagedAgents else { return }
        mutateStoredGenerationControls { storedControls in
            storedControls.clearClaudeManagedAgentSessionState()
        }
    }

    func recordClaudeManagedAgentHistoryMutation(removedMessages: [MessageEntity]) {
        guard !removedMessages.isEmpty else { return }
        guard providerType == .claudeManagedAgents else { return }
        clearClaudeManagedAgentSessionPersistence(for: conversationEntity)
    }
}
