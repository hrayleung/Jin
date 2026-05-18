import SwiftData
import SwiftUI

// MARK: - Conversation Helpers (sidebar-row helpers now live in ChatsSidebarSectionView)

extension ContentView {
    func fetchPersistedConversations() -> [ConversationEntity] {
        (try? modelContext.fetch(FetchDescriptor<ConversationEntity>())) ?? []
    }

    func fetchPersistedConversation(id: UUID) -> ConversationEntity? {
        fetchPersistedConversations().first { $0.id == id }
    }

    func fetchPersistedConversationsByActivityDescending() -> [ConversationEntity] {
        ConversationActivitySupport.sortedByActivityDescending(fetchPersistedConversations())
    }

    func providerName(for providerID: String) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
    }

    func providerIconID(for providerID: String) -> String? {
        providers.first(where: { $0.id == providerID })?.resolvedProviderIconID
    }

    func activeProviderID(for conversation: ConversationEntity) -> String {
        conversation.providerID
    }

    func activeModelID(for conversation: ConversationEntity) -> String {
        conversation.modelID
    }

    func providerName(for conversation: ConversationEntity) -> String {
        providerName(for: conversation.providerID)
    }

    func providerIconID(for conversation: ConversationEntity) -> String? {
        providerIconID(for: conversation.providerID)
    }

    func modelName(for conversation: ConversationEntity) -> String {
        let providerID = conversation.providerID
        let modelID = conversation.modelID
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return modelID
        }

        if ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            let storedControls = try? JSONDecoder().decode(GenerationControls.self, from: conversation.modelConfigData)
            return ClaudeManagedAgentResolutionSupport.resolvedConversationDisplayName(
                threadModelID: modelID,
                storedControls: storedControls,
                applyProviderDefaults: { controls in
                    provider.applyClaudeManagedDefaults(into: &controls)
                }
            )
        }

        return provider.allModels.first(where: { $0.id == modelID })?.name ?? modelID
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
