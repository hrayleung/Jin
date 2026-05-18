import Foundation

// MARK: - Chat Naming

extension ChatView {

    var isChatNamingPluginEnabled: Bool {
        AppPreferences.isPluginEnabled("chat_naming")
    }

    var chatNamingMode: ChatNamingMode {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: AppPreferenceKeys.chatNamingMode) ?? ChatNamingMode.firstRoundFixed.rawValue
        return ChatNamingMode(rawValue: raw) ?? .firstRoundFixed
    }

    @MainActor
    func resolvedChatNamingTarget() -> (provider: ProviderConfig, modelID: String)? {
        guard isChatNamingPluginEnabled else { return nil }

        let defaults = UserDefaults.standard
        return ChatNamingModelSupport.resolvedTarget(
            providers: providers,
            providerID: defaults.string(forKey: AppPreferenceKeys.chatNamingProviderID) ?? "",
            modelID: defaults.string(forKey: AppPreferenceKeys.chatNamingModelID) ?? ""
        )
    }

    @MainActor
    func maybeAutoRenameConversation(
        targetProvider: ProviderConfig,
        targetModelID: String,
        history: [Message],
        finalAssistantMessage: Message
    ) async {
        guard let latestUser = history.last(where: { $0.role == .user }) else { return }

        if conversationEntity.titleEditedByUser == true { return }

        if chatNamingMode == .firstRoundFixed,
           conversationEntity.title != "New Chat" {
            return
        }

        let promptTemplate = customChatNamingPromptTemplate()

        do {
            let title = try await conversationTitleGenerator.generateTitle(
                providerConfig: targetProvider,
                modelID: targetModelID,
                contextMessages: [latestUser, finalAssistantMessage],
                maxCharacters: 24,
                promptTemplate: promptTemplate
            )
            conversationEntity.title = title
            try? modelContext.save()
        } catch {
            guard conversationEntity.title == "New Chat" else { return }
            let fallback = ConversationTitleGenerator.normalizeTitle(
                fallbackTitleFromMessage(latestUser),
                maxCharacters: 24
            )
            guard !fallback.isEmpty else { return }
            conversationEntity.title = fallback
            try? modelContext.save()
        }
    }

    func customChatNamingPromptTemplate() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.chatNamingPromptTemplate) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func makeConversationTitle(from userText: String) -> String {
        ChatMessagePreparationSupport.makeConversationTitle(from: userText)
    }

    func fallbackTitleFromMessage(_ message: Message) -> String {
        ChatMessagePreparationSupport.fallbackTitleFromMessage(message)
    }
}
