import SwiftUI
import SwiftData

// MARK: - Conversation CRUD & Selection

extension ContentView {
    func selectConversation(_ conversation: ConversationEntity) {
        let assistant = conversation.assistant
            ?? assistants.first(where: { $0.id == "default" })
            ?? assistants.first

        // Instant swap. Animating a destination change here cross-fades the
        // outgoing ChatView against an incoming one whose state is still
        // being rebuilt, which surfaces as visible jank.
        if let assistant {
            selectedAssistant = assistant
        }
        selectedConversation = conversation
    }

    func createNewConversation() {
        bootstrapDefaultProvidersIfNeeded()
        bootstrapDefaultAssistantsIfNeeded()

        let discardedConversationID = discardSelectedEmptyConversationIfNeeded()

        guard let assistant = selectedAssistant ?? assistants.first(where: { $0.id == "default" }) ?? assistants.first else {
            if discardedConversationID != nil {
                selectedConversation = nil
            }
            return
        }

        let lastConversation: ConversationEntity?
        if let selectedConversation, selectedConversation.id != discardedConversationID {
            lastConversation = selectedConversation
        } else {
            lastConversation = fetchPersistedConversationsByActivityDescending().first { conversation in
                conversation.id != discardedConversationID && !conversation.messages.isEmpty
            }
        }

        var providerID: String
        var modelID: String

        switch newChatModelMode {
        case .lastUsed:
            let candidateProviderID = lastConversation.map { activeProviderID(for: $0) }
            let resolvedProviderID = candidateProviderID.flatMap { candidate in
                providers.first(where: { $0.id == candidate })?.id
            }
            providerID = resolvedProviderID
                ?? providers.first(where: { $0.id == "openai" })?.id
                ?? providers.first?.id
                ?? "openai"

            let candidateModelID = lastConversation.map { activeModelID(for: $0) }
            let models = modelsForProvider(providerID)
            if let candidateModelID, models.contains(where: { $0.id == candidateModelID }) {
                modelID = candidateModelID
            } else {
                modelID = defaultModelID(for: providerID)
            }

        case .fixed:
            let resolvedProviderID = providers.first(where: { $0.id == newChatFixedProviderID })?.id
            providerID = resolvedProviderID
                ?? providers.first(where: { $0.id == "openai" })?.id
                ?? providers.first?.id
                ?? "openai"

            let models = modelsForProvider(providerID)
            if models.contains(where: { $0.id == newChatFixedModelID }) {
                modelID = newChatFixedModelID
            } else {
                modelID = defaultModelID(for: providerID)
            }
        }

        let inheritedControls = lastConversation.flatMap { conversation -> GenerationControls? in
            try? JSONDecoder().decode(GenerationControls.self, from: conversation.modelConfigData)
        }
        var controls = inheritedControls ?? GenerationControls()
        controls.clearClaudeManagedAgentSessionState()
        if let provider = providers.first(where: { $0.id == providerID }),
           ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            provider.applyClaudeManagedDefaults(into: &controls)
        }
        switch newChatMCPMode {
        case .lastUsed:
            break

        case .fixed:
            guard newChatFixedMCPEnabled else {
                controls.mcpTools = MCPToolsControls(enabled: false, enabledServerIDs: nil)
                break
            }

            if newChatFixedMCPUseAllServers {
                controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
            } else {
                let ids = AppPreferences.decodeStringArrayJSON(newChatFixedMCPServerIDsJSON)
                controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: ids)
            }
        }

        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
        }

        let controlsData = (try? JSONEncoder().encode(controls)) ?? Data()
        let conversation = ConversationEntity(
            title: "New Chat",
            artifactsEnabled: false,
            systemPrompt: nil,
            providerID: providerID,
            modelID: modelID,
            modelConfigData: controlsData,
            assistant: assistant
        )

        selectConversation(conversation)
    }

    func requestDeleteConversation(_ conversation: ConversationEntity) {
        conversationPendingDeletion = conversation
        showingDeleteConversationConfirmation = true
    }

    func deleteConversation(_ conversation: ConversationEntity) {
        streamingStore.cancel(conversationID: conversation.id)
        streamingStore.endSession(conversationID: conversation.id)
        if isPersistedConversation(conversation) {
            modelContext.delete(conversation)
        }
        if selectedConversation == conversation {
            selectedConversation = nil
        }
        conversationPendingDeletion = nil
    }

    func deleteConversations(at offsets: IndexSet, in sourceList: [ConversationEntity]) {
        for index in offsets {
            let conversation = sourceList[index]
            streamingStore.cancel(conversationID: conversation.id)
            streamingStore.endSession(conversationID: conversation.id)
            modelContext.delete(conversation)
            if selectedConversation == conversation {
                selectedConversation = nil
            }
        }
    }

    func requestRenameConversation(_ conversation: ConversationEntity) {
        conversationPendingRename = conversation
        renameConversationDraftTitle = conversation.title
        showingRenameConversationAlert = true
    }

    func applyManualConversationRename() {
        guard let conversation = conversationPendingRename else { return }
        guard let trimmed = ConversationRenameSupport.normalizedTitle(renameConversationDraftTitle) else { return }

        conversation.title = trimmed
        try? modelContext.save()
        conversationPendingRename = nil
        showingRenameConversationAlert = false
    }

    func toggleConversationStar(_ conversation: ConversationEntity) {
        conversation.isStarred = !(conversation.isStarred == true)
        try? modelContext.save()
    }

    func persistConversationIfNeeded(_ conversation: ConversationEntity) {
        guard !isPersistedConversation(conversation) else { return }
        modelContext.insert(conversation)
    }

    func isPersistedConversation(_ conversation: ConversationEntity) -> Bool {
        conversation.modelContext != nil
    }

    @discardableResult
    func discardSelectedEmptyConversationIfNeeded() -> UUID? {
        guard let conversation = selectedConversation, conversation.messages.isEmpty else {
            return nil
        }

        let conversationID = conversation.id
        streamingStore.cancel(conversationID: conversationID)
        streamingStore.endSession(conversationID: conversationID)

        if isPersistedConversation(conversation) {
            modelContext.delete(conversation)
        }

        if conversationPendingDeletion == conversation {
            conversationPendingDeletion = nil
            showingDeleteConversationConfirmation = false
        }

        if conversationPendingRename == conversation {
            conversationPendingRename = nil
            showingRenameConversationAlert = false
            renameConversationDraftTitle = ""
        }

        if regeneratingConversationID == conversationID {
            regeneratingConversationID = nil
        }

        return conversationID
    }

}
