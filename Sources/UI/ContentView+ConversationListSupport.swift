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

    func fetchPersistedConversationsByUpdatedAtDescending() -> [ConversationEntity] {
        fetchPersistedConversations().sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    func providerName(for providerID: String) -> String {
        providers.first(where: { $0.id == providerID })?.name ?? providerID
    }

    func providerIconID(for providerID: String) -> String? {
        providers.first(where: { $0.id == providerID })?.resolvedProviderIconID
    }

    /// Resolve the active thread's `providerID` for sidebar rendering. Falls
    /// back to the conversation's legacy snapshot field when threads haven't
    /// been seeded yet (very old conversations created before multi-model).
    func activeProviderID(for conversation: ConversationEntity) -> String {
        let sortedThreads = ChatThreadSupport.sortedThreads(in: conversation.modelThreads)
        if let active = ChatThreadSupport.activeThread(
            in: sortedThreads,
            preferredID: conversation.activeThreadID
        ) {
            return active.providerID
        }
        return conversation.providerID
    }

    /// Mirror of `activeProviderID(for:)` returning the active thread's
    /// `modelID`.
    func activeModelID(for conversation: ConversationEntity) -> String {
        let sortedThreads = ChatThreadSupport.sortedThreads(in: conversation.modelThreads)
        if let active = ChatThreadSupport.activeThread(
            in: sortedThreads,
            preferredID: conversation.activeThreadID
        ) {
            return active.modelID
        }
        return conversation.modelID
    }

    func providerName(for conversation: ConversationEntity) -> String {
        providerName(for: activeProviderID(for: conversation))
    }

    func providerIconID(for conversation: ConversationEntity) -> String? {
        providerIconID(for: activeProviderID(for: conversation))
    }

    func modelName(for conversation: ConversationEntity) -> String {
        let providerID = activeProviderID(for: conversation)
        let modelID = activeModelID(for: conversation)
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return modelID
        }

        if ProviderType(rawValue: provider.typeRaw) == .claudeManagedAgents {
            let configData = conversation.modelThreads.first(where: { $0.id == conversation.activeThreadID })?.modelConfigData
                ?? conversation.modelThreads.first?.modelConfigData
                ?? conversation.modelConfigData
            let storedControls = try? JSONDecoder().decode(GenerationControls.self, from: configData)
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
