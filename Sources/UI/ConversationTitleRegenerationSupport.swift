import Foundation

enum ConversationTitleRegenerationSupport {
    static func contextMessages(from history: [Message]) -> [Message] {
        guard !history.isEmpty else { return [] }

        if let assistantIndex = history.lastIndex(where: { $0.role == .assistant }) {
            let latestAssistant = history[assistantIndex]
            let prior = history[..<assistantIndex]
            if let latestUserBeforeAssistant = prior.last(where: { $0.role == .user }) {
                return [latestUserBeforeAssistant, latestAssistant]
            }
            return [latestAssistant]
        }

        if let latestUser = history.last(where: { $0.role == .user }) {
            return [latestUser]
        }

        return []
    }
}
