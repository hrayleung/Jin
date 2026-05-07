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

        if chatNamingMode == .firstRoundFixed {
            let current = conversationEntity.title
            if current != "New Chat" {
                return
            }
        }

        do {
            let title = try await conversationTitleGenerator.generateTitle(
                providerConfig: targetProvider,
                modelID: targetModelID,
                contextMessages: [latestUser, finalAssistantMessage],
                maxCharacters: 40
            )

            let normalized = ConversationTitleGenerator.normalizeTitle(title, maxCharacters: 40)
            guard !normalized.isEmpty else { return }
            conversationEntity.title = normalized
            try? modelContext.save()
        } catch {
            if chatNamingMode == .firstRoundFixed {
                if conversationEntity.title == "New Chat" {
                    conversationEntity.title = fallbackTitleFromMessage(latestUser)
                    try? modelContext.save()
                }
            }
        }
    }

    func makeConversationTitle(from userText: String) -> String {
        ChatMessagePreparationSupport.makeConversationTitle(from: userText)
    }

    func fallbackTitleFromMessage(_ message: Message) -> String {
        ChatMessagePreparationSupport.fallbackTitleFromMessage(message)
    }
}
