import SwiftUI

// MARK: - Conversation Filtering & Helpers

extension ContentView {
    var normalizedConversationSearchQuery: String {
        ContentViewConversationListSupport.normalizedSearchQuery(searchText)
    }

    var filteredConversations: [ConversationEntity] {
        let query = normalizedConversationSearchQuery
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
        let query = normalizedConversationSearchQuery
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
}
