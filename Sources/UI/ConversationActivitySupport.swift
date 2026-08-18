import Foundation

enum ConversationActivitySupport {
    /// Reads the denormalized `lastActivityAt`. The fallback recomputes from
    /// the relationship and is reached only by rows created before that
    /// attribute existed, until post-launch maintenance backfills them —
    /// deriving this per conversation is what used to freeze the sidebar.
    static func activityDate(for conversation: ConversationEntity) -> Date {
        conversation.lastActivityAt ?? conversation.computedActivityDate()
    }

    static func sortedByActivityDescending(_ conversations: [ConversationEntity]) -> [ConversationEntity] {
        conversations
            .map { conversation in
                (conversation: conversation, activityDate: activityDate(for: conversation))
            }
            .sorted { lhs, rhs in
                if lhs.activityDate != rhs.activityDate { return lhs.activityDate > rhs.activityDate }
                return lhs.conversation.createdAt > rhs.conversation.createdAt
            }
            .map(\.conversation)
    }
}
