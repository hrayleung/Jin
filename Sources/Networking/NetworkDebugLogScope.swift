import Foundation

struct NetworkDebugLogContext: Sendable {
    let conversationID: String?

    init(conversationID: String? = nil) {
        self.conversationID = Self.normalized(conversationID)
    }

    var jsonObject: [String: String] {
        var out: [String: String] = [:]
        if let conversationID {
            out["conversation_id"] = conversationID
        }
        return out
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmedNonEmpty
    }
}

enum NetworkDebugLogScope {
    @TaskLocal
    static var current: NetworkDebugLogContext?
}
