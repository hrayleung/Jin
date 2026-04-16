import SwiftUI
import SwiftData

// MARK: - Conversation CRUD & Selection

extension ContentView {
    func selectConversation(_ conversation: ConversationEntity) {
        let assistant = conversation.assistant
            ?? assistants.first(where: { $0.id == "default" })
            ?? assistants.first

        withAnimation(.easeInOut(duration: 0.15)) {
            if let assistant {
                selectedAssistant = assistant
            }
            selectedConversation = conversation
        }
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
            lastConversation = conversations.first { conversation in
                conversation.id != discardedConversationID && !conversation.messages.isEmpty
            }
        }

        var providerID: String
        var modelID: String

        switch newChatModelMode {
        case .lastUsed:
            let candidateProviderID = lastConversation?.providerID
            let resolvedProviderID = candidateProviderID.flatMap { candidate in
                providers.first(where: { $0.id == candidate })?.id
            }
            providerID = resolvedProviderID
                ?? providers.first(where: { $0.id == "openai" })?.id
                ?? providers.first?.id
                ?? "openai"

            let candidateModelID = lastConversation?.modelID
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

        let inheritedControls = lastConversation.flatMap { conversation in
            try? JSONDecoder().decode(GenerationControls.self, from: conversation.modelConfigData)
        }
        var controls = inheritedControls ?? GenerationControls()
        controls.codexResumeThreadID = nil
        controls.codexPendingRollbackTurns = 0
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
        let initialThread = ConversationModelThreadEntity(
            providerID: providerID,
            modelID: modelID,
            modelConfigData: controlsData,
            displayOrder: 0,
            isSelected: true,
            isPrimary: true
        )
        initialThread.conversation = conversation
        conversation.modelThreads.append(initialThread)
        conversation.activeThreadID = initialThread.id

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
        let trimmed = renameConversationDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

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

    // MARK: - Title Regeneration

    @MainActor
    func regenerateConversationTitle(_ conversation: ConversationEntity) async {
        guard regeneratingConversationID != conversation.id else { return }

        guard let target = resolvedChatNamingTargetForRegeneration() else {
            titleRegenerationErrorMessage = "Please choose a provider/model in Settings → Plugins → Chat Naming first."
            showingTitleRegenerationError = true
            return
        }

        let contextMessages = latestMessagesForTitleRegeneration(in: conversation)
        guard !contextMessages.isEmpty else {
            titleRegenerationErrorMessage = "No usable conversation messages found to generate a title."
            showingTitleRegenerationError = true
            return
        }

        regeneratingConversationID = conversation.id
        defer { regeneratingConversationID = nil }

        do {
            let title = try await conversationTitleGenerator.generateTitle(
                providerConfig: target.provider,
                modelID: target.modelID,
                contextMessages: contextMessages,
                maxCharacters: 40
            )
            let normalized = ConversationTitleGenerator.normalizeTitle(title, maxCharacters: 40)
            guard !normalized.isEmpty else {
                throw LLMError.decodingError(message: "Generated empty title.")
            }

            conversation.title = normalized
        } catch {
            titleRegenerationErrorMessage = error.localizedDescription
            showingTitleRegenerationError = true
        }
    }

    // MARK: - Conversation Filtering & Helpers

    var filteredConversations: [ConversationEntity] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !query.isEmpty

        let baseConversations = conversations.filter { conversation in
            guard !conversation.messages.isEmpty else { return false }
            if isSearching { return true }
            guard let selectedAssistant else { return true }
            return conversation.assistant?.id == selectedAssistant.id
        }

        guard isSearching else { return baseConversations }

        let lowered = query.lowercased()
        return baseConversations.filter { conversation in
            if conversation.title.lowercased().contains(lowered)
                || conversation.modelID.lowercased().contains(lowered)
                || providerName(for: conversation.providerID).lowercased().contains(lowered) {
                return true
            }
            return searchCache.searchableText(for: conversation)
                .localizedCaseInsensitiveContains(query)
        }
    }

    func searchSnippet(for conversation: ConversationEntity) -> String? {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let lowered = query.lowercased()
        if conversation.title.lowercased().contains(lowered) { return nil }
        return ConversationSearchCache.extractSnippet(
            from: searchCache.searchableText(for: conversation),
            query: query
        )
    }

    var groupedConversations: [(key: String, value: [ConversationEntity])] {
        ConversationGrouping.groupedConversations(filteredConversations)
    }

    var conversationListSelectionBinding: Binding<ConversationEntity?> {
        Binding(
            get: {
                guard let selectedConversation else { return nil }
                return conversations.first(where: { $0.id == selectedConversation.id })
            },
            set: { newValue in
                guard let newValue else {
                    guard let current = selectedConversation else { return }
                    if conversations.contains(where: { $0.id == current.id }) {
                        selectedConversation = nil
                    }
                    return
                }

                selectConversation(newValue)
            }
        )
    }

    func providerName(for providerID: String) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
    }

    func providerIconID(for providerID: String) -> String? {
        providers.first(where: { $0.id == providerID })?.resolvedProviderIconID
    }

    func modelName(for conversation: ConversationEntity) -> String {
        guard let provider = providers.first(where: { $0.id == conversation.providerID }) else {
            return conversation.modelID
        }

        if ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            let storedControls = try? JSONDecoder().decode(GenerationControls.self, from: conversation.modelConfigData)
            return ClaudeManagedAgentResolutionSupport.resolvedConversationDisplayName(
                threadModelID: conversation.modelID,
                storedControls: storedControls,
                applyProviderDefaults: { controls in
                    provider.applyClaudeManagedDefaults(into: &controls)
                }
            )
        }

        return provider.allModels.first(where: { $0.id == conversation.modelID })?.name ?? conversation.modelID
    }

    func modelName(id modelID: String, providerID: String) -> String {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return modelID
        }

        if ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            var controls = GenerationControls()
            provider.applyClaudeManagedDefaults(into: &controls)
            return ClaudeManagedAgentRuntime.resolvedDisplayName(
                threadModelID: modelID,
                controls: controls
            )
        }

        return provider.allModels.first(where: { $0.id == modelID })?.name ?? modelID
    }

    func requestRenameSelectedConversation() {
        guard let selectedConversation else { return }
        requestRenameConversation(selectedConversation)
    }

    func toggleSelectedConversationStar() {
        guard let selectedConversation else { return }
        toggleConversationStar(selectedConversation)
    }

    func requestDeleteSelectedConversation() {
        guard let selectedConversation else { return }
        requestDeleteConversation(selectedConversation)
    }

    // MARK: - Model Resolution

    func modelsForProvider(_ providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return []
        }
        return provider.selectableModels
    }

    func defaultModelID(for providerID: String) -> String {
        if let provider = providers.first(where: { $0.id == providerID }),
           ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            return provider.selectableModels.first?.id
                ?? ClaudeManagedAgentRuntime.syntheticThreadModelID(
                    providerID: providerID,
                    agentID: provider.claudeManagedDefaultAgentID,
                    environmentID: provider.claudeManagedDefaultEnvironmentID
                )
        }

        let models = modelsForProvider(providerID)
        guard !models.isEmpty else {
            switch providerID {
            case "anthropic":
                return "claude-opus-4-7"
            case "xai":
                return "grok-4-1-fast"
            case "deepseek":
                return "deepseek-chat"
            case "zhipu-coding-plan":
                return "glm-5"
            case "minimax", "minimax-coding-plan":
                return "MiniMax-M2.7"
            case "deepinfra":
                return "zai-org/GLM-5"
            case "fireworks":
                return "fireworks/qwen3p6-plus"
            case "together":
                return "moonshotai/Kimi-K2.5"
            case "cerebras":
                return "qwen-3-235b-a22b-instruct-2507"
            case "sambanova":
                return "MiniMax-M2.5"
            case "vercel-ai-gateway":
                return "openai/gpt-5.2"
            case "vertexai":
                return "gemini-3-pro-preview"
            default:
                return "gpt-5.2"
            }
        }

        if providerID == "openai", let gpt52 = models.first(where: { $0.id == "gpt-5.2" }) {
            return gpt52.id
        }
        if providerID == "vercel-ai-gateway", let gpt52 = models.first(where: { $0.id == "openai/gpt-5.2" }) {
            return gpt52.id
        }
        if providerID == "vercel-ai-gateway", let gpt5 = models.first(where: { $0.id == "openai/gpt-5" }) {
            return gpt5.id
        }
        if providerID == "anthropic", let opus47 = models.first(where: { $0.id == "claude-opus-4-7" }) {
            return opus47.id
        }
        if providerID == "anthropic", let opus46 = models.first(where: { $0.id == "claude-opus-4-6" }) {
            return opus46.id
        }
        if providerID == "anthropic", let sonnet46 = models.first(where: { $0.id == "claude-sonnet-4-6" }) {
            return sonnet46.id
        }
        if providerID == "anthropic", let sonnet45 = models.first(where: { $0.id == "claude-sonnet-4-5-20250929" }) {
            return sonnet45.id
        }
        if providerID == "xai", let grok41Fast = models.first(where: { $0.id == "grok-4-1-fast" }) {
            return grok41Fast.id
        }
        if providerID == "deepseek", let deepseekChat = models.first(where: { $0.id == "deepseek-chat" }) {
            return deepseekChat.id
        }
        if providerID == "zhipu-coding-plan", let glm5 = models.first(where: { $0.id.lowercased() == "glm-5" }) {
            return glm5.id
        }
        if providerID == "zhipu-coding-plan", let glm47 = models.first(where: { $0.id.lowercased() == "glm-4.7" }) {
            return glm47.id
        }
        if providerID == "minimax" || providerID == "minimax-coding-plan",
           let m27 = models.first(where: { $0.id == "MiniMax-M2.7" }) {
            return m27.id
        }
        if providerID == "minimax" || providerID == "minimax-coding-plan",
           let m25 = models.first(where: { $0.id == "MiniMax-M2.5" }) {
            return m25.id
        }
        if providerID == "deepinfra", let glm5 = models.first(where: { $0.id == "zai-org/GLM-5" }) {
            return glm5.id
        }
        if providerID == "deepinfra", let qwen397 = models.first(where: { $0.id == "Qwen/Qwen3.5-397B-A17B" }) {
            return qwen397.id
        }
        if providerID == "fireworks",
           let qwen36Plus = models.first(where: {
               $0.id == "fireworks/qwen3p6-plus" || $0.id == "accounts/fireworks/models/qwen3p6-plus"
           }) {
            return qwen36Plus.id
        }
        if providerID == "fireworks",
           let deepSeekV32 = models.first(where: {
               $0.id == "fireworks/deepseek-v3p2" || $0.id == "accounts/fireworks/models/deepseek-v3p2"
           }) {
            return deepSeekV32.id
        }
        if providerID == "fireworks",
           let kimiK2Instruct = models.first(where: {
               $0.id == "fireworks/kimi-k2-instruct-0905"
                   || $0.id == "accounts/fireworks/models/kimi-k2-instruct-0905"
           }) {
            return kimiK2Instruct.id
        }
        if providerID == "together", let kimiK2p5 = models.first(where: { $0.id == "moonshotai/Kimi-K2.5" }) {
            return kimiK2p5.id
        }
        if providerID == "together", let glm5 = models.first(where: { $0.id == "zai-org/GLM-5" }) {
            return glm5.id
        }
        if providerID == "cerebras",
           let qwen235 = models.first(where: { $0.id == "qwen-3-235b-a22b-instruct-2507" }) {
            return qwen235.id
        }
        if providerID == "cerebras", let glm47 = models.first(where: { $0.id == "zai-glm-4.7" }) {
            return glm47.id
        }
        if providerID == "sambanova", let miniMax = models.first(where: { $0.id == "MiniMax-M2.5" }) {
            return miniMax.id
        }
        if providerID == "sambanova", let deepSeekV31 = models.first(where: { $0.id == "DeepSeek-V3.1" }) {
            return deepSeekV31.id
        }
        if providerID == "vertexai", let gemini3Pro = models.first(where: { $0.id == "gemini-3-pro-preview" }) {
            return gemini3Pro.id
        }
        if let first = models.first?.id {
            return first
        }

        if providerID == "anthropic" {
            return "claude-opus-4-7"
        }
        if providerID == "vercel-ai-gateway" {
            return "openai/gpt-5.2"
        }
        return "gpt-5.2"
    }

    // MARK: - Private Helpers

    func resolvedChatNamingTargetForRegeneration() -> (provider: ProviderConfig, modelID: String)? {
        let defaults = UserDefaults.standard
        let providerID = (defaults.string(forKey: AppPreferenceKeys.chatNamingProviderID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = (defaults.string(forKey: AppPreferenceKeys.chatNamingModelID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !providerID.isEmpty, !modelID.isEmpty else { return nil }
        guard let providerEntity = providers.first(where: { $0.id == providerID }),
              let provider = try? providerEntity.toDomain() else {
            return nil
        }

        let models = providerEntity.enabledModels
        guard models.contains(where: { $0.id == modelID }) else { return nil }

        return (provider, modelID)
    }

    func latestMessagesForTitleRegeneration(in conversation: ConversationEntity) -> [Message] {
        let history = conversation.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .compactMap { try? $0.toDomain() }

        guard !history.isEmpty else { return [] }

        if let assistantIndex = history.lastIndex(where: { $0.role == .assistant }) {
            let latestAssistant = history[assistantIndex]
            let prior = history[..<assistantIndex]
            if let latestUserBeforeAssistant = prior.last(where: { $0.role == .user }) {
                return [latestUserBeforeAssistant, latestAssistant]
            }
            return [latestAssistant]
        }

        if let latestUser = history.last(where: { $0.role == .user }) {
            return [latestUser]
        }

        return []
    }
}
