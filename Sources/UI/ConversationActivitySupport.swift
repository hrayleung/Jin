import Foundation

enum ConversationActivitySupport {
    static func activityDate(for conversation: ConversationEntity) -> Date {
        latestUserMessageDate(for: conversation)
            ?? latestMessageDate(for: conversation)
            ?? conversation.createdAt
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

    private static func latestUserMessageDate(for conversation: ConversationEntity) -> Date? {
        conversation.messages
            .filter { $0.role == MessageRole.user.rawValue }
            .map(\.timestamp)
            .max()
    }

    private static func latestMessageDate(for conversation: ConversationEntity) -> Date? {
        conversation.messages
            .map(\.timestamp)
            .max()
    }
}
