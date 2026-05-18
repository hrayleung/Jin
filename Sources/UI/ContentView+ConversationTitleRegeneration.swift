import Foundation

// MARK: - Title Regeneration

extension ContentView {
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

        let promptTemplate = customChatNamingPromptTemplate()

        do {
            let title = try await conversationTitleGenerator.generateTitle(
                providerConfig: target.provider,
                modelID: target.modelID,
                contextMessages: contextMessages,
                maxCharacters: 24,
                promptTemplate: promptTemplate
            )
            conversation.title = title
        } catch {
            titleRegenerationErrorMessage = error.localizedDescription
            showingTitleRegenerationError = true
        }
    }

    func customChatNamingPromptTemplate() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.chatNamingPromptTemplate) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func resolvedChatNamingTargetForRegeneration() -> (provider: ProviderConfig, modelID: String)? {
        let defaults = UserDefaults.standard
        return ChatNamingModelSupport.resolvedTarget(
            providers: providers,
            providerID: defaults.string(forKey: AppPreferenceKeys.chatNamingProviderID) ?? "",
            modelID: defaults.string(forKey: AppPreferenceKeys.chatNamingModelID) ?? ""
        )
    }

    func latestMessagesForTitleRegeneration(in conversation: ConversationEntity) -> [Message] {
        let history = conversation.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .compactMap { try? $0.toDomain() }

        return ConversationTitleRegenerationSupport.contextMessages(from: history)
    }
}
