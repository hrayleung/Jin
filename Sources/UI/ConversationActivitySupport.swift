import Foundation

enum ConversationActivitySupport {
    static func activityDate(for conversation: ConversationEntity) -> Date {
        latestUserMessageDate(for: conversation)
            ?? latestMessageDate(for: conversation)
            ?? conversation.createdAt
    }

    static func sortedByActivityDescending(_ conversations: [ConversationEntity]) -> [ConversationEntity] {
        conversations.sorted { lhs, rhs in
            let lhsDate = activityDate(for: lhs)
            let rhsDate = activityDate(for: rhs)
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.createdAt > rhs.createdAt
        }
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
