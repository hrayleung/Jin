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
