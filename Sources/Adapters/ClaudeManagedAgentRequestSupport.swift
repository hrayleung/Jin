import Foundation

enum ClaudeManagedAgentRequestSupport {
    static func sessionCreationBody(agentID: String, environmentID: String) -> [String: Any] {
        // Per managed-agents-2026-04-01 docs, `agent` accepts either the agent
        // ID string (pins the latest version) or a full agent object.
        [
            "agent": agentID,
            "environment_id": environmentID
        ]
    }

    static func systemPrompt(from messages: [Message]) -> String? {
        messages.first(where: { $0.role == .system })
            .flatMap(extractPlainText)
    }
}

extension ClaudeManagedAgentRequestSupport {
    static func extractPlainText(_ message: Message) -> String? {
        let text = message.content.compactMap { part -> String? in
            if case .text(let text) = part {
                return text.trimmedNonEmpty
            }
            return nil
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
