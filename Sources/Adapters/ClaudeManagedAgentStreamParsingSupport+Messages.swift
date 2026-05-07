import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    static func appendMessageEvents(
        from object: [String: JSONValue],
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        let messageID = object.string(at: ["id"]) ?? UUID().uuidString

        appendMessageStartIfNeeded(messageID: messageID, state: &state, events: &events)
        appendTextDeltas(from: object, events: &events)
        appendCitationSearchActivity(from: object, messageID: messageID, events: &events)
    }

    static func appendMessageStartIfNeeded(
        messageID: String,
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        guard !state.didEmitMessageStart else { return }
        state.didEmitMessageStart = true
        state.currentMessageID = messageID
        events.append(.messageStart(id: messageID))
    }

    static func appendTextDeltas(
        from object: [String: JSONValue],
        events: inout [StreamEvent]
    ) {
        for text in extractTextContent(from: object) where !text.isEmpty {
            events.append(.contentDelta(.text(text)))
        }
    }

    static func appendCitationSearchActivity(
        from object: [String: JSONValue],
        messageID: String,
        events: inout [StreamEvent]
    ) {
        let extractedSources = extractSearchSources(from: object)
        guard !extractedSources.isEmpty else { return }

        events.append(.searchActivity(
            SearchActivity(
                id: "\(messageID):sources",
                type: "url_citation",
                status: .completed,
                arguments: searchActivityArguments(sources: extractedSources)
            )
        ))
    }

    static func extractTextContent(from object: [String: JSONValue]) -> [String] {
        if let texts = contentTextParts(from: object), !texts.isEmpty {
            return texts
        }

        if let fallback = fallbackTextContent(from: object) {
            return [fallback]
        }

        return []
    }

    static func contentTextParts(from object: [String: JSONValue]) -> [String]? {
        guard let parts = object.array(at: ["content"]) else { return nil }
        return parts.compactMap(contentTextPart(from:))
    }

    static func contentTextPart(from value: JSONValue) -> String? {
        guard let partObject = value.objectValue else { return nil }
        guard partObject.string(at: ["type"]) == "text" else { return nil }
        return partObject.string(at: ["text"])
    }

    static func fallbackTextContent(from object: [String: JSONValue]) -> String? {
        object.string(at: ["delta", "text"]) ?? object.string(at: ["text"])
    }
}
