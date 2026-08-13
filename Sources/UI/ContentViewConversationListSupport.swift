import Foundation

enum ContentViewConversationListSupport {
    /// Bounded window used when New Chat needs a last-used conversation after
    /// discarding an empty draft. Fetching and activity-sorting the whole store
    /// faults every conversation's messages on the tap.
    static let lastUsedConversationFetchLimit = 8

    static func normalizedSearchQuery(_ searchText: String) -> String {
        searchText.trimmedNonEmpty ?? ""
    }

    static func lastUsedConversation<Conversation>(
        from conversations: [Conversation],
        excluding excludedID: UUID?,
        id: (Conversation) -> UUID,
        hasMessages: (Conversation) -> Bool
    ) -> Conversation? {
        conversations.first { conversation in
            id(conversation) != excludedID && hasMessages(conversation)
        }
    }
}
