import Foundation

struct NetworkDebugLogContext: Sendable {
    let conversationID: String?
    let threadID: String?
    let turnID: String?

    init(
        conversationID: String? = nil,
        threadID: String? = nil,
        turnID: String? = nil
    ) {
        self.conversationID = Self.normalized(conversationID)
        self.threadID = Self.normalized(threadID)
        self.turnID = Self.normalized(turnID)
    }

    var jsonObject: [String: String] {
        var out: [String: String] = [:]
        if let conversationID {
            out["conversation_id"] = conversationID
        }
        if let threadID {
            out["thread_id"] = threadID
        }
        if let turnID {
            out["turn_id"] = turnID
        }
        return out
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum NetworkDebugLogScope {
    @TaskLocal
    static var current: NetworkDebugLogContext?
}
