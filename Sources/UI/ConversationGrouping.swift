import Foundation

enum ConversationGrouping {
    static func groupedConversations(
        _ conversations: [ConversationEntity],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(key: String, value: [ConversationEntity])] {
        let starred = conversations
            .filter { $0.isStarred == true }
            .sorted { $0.updatedAt > $1.updatedAt }

        let unstarred = conversations.filter { $0.isStarred != true }
        let grouped = Dictionary(grouping: unstarred) { conversation in
            relativeDateString(for: conversation.updatedAt, now: now, calendar: calendar)
        }

        var result: [(key: String, value: [ConversationEntity])] = []
        if !starred.isEmpty {
            result.append((key: "Starred", value: starred))
        }

        for key in ["Today", "Yesterday", "Previous 7 Days", "Older"] {
            guard let values = grouped[key] else { continue }
            result.append((key: key, value: values.sorted { $0.updatedAt > $1.updatedAt }))
        }

        return result
    }

    static func relativeDateString(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo {
            return "Previous 7 Days"
        }

        return "Older"
    }
}
