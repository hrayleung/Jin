import Foundation

extension ClaudeManagedAgentStreamParsingSupport {
    enum ToolResultKind {
        case agent
        case mcp
    }

    static func completeToolResult(
        from object: [String: JSONValue],
        kind: ToolResultKind,
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        guard let referencedID = toolResultReferencedID(from: object, kind: kind) else {
            return
        }

        completeToolActivity(
            referencedID: referencedID,
            object: object,
            state: &state,
            events: &events
        )
    }

    static func completeToolActivity(
        referencedID: String,
        object: [String: JSONValue],
        state: inout ClaudeManagedAgentsStreamState,
        events: inout [StreamEvent]
    ) {
        if let activity = state.pendingSearchActivities[referencedID] {
            let completed = completedSearchActivity(from: object, fallback: activity)
            state.pendingSearchActivities.removeValue(forKey: referencedID)
            events.append(.searchActivity(completed))
        }
    }

    static func toolResultReferencedID(
        from object: [String: JSONValue],
        kind: ToolResultKind
    ) -> String? {
        switch kind {
        case .agent:
            return object.string(at: ["tool_use_id"])
        case .mcp:
            return object.string(at: ["mcp_tool_use_id"])
        }
    }

    static func completedSearchActivity(
        from object: [String: JSONValue],
        fallback: SearchActivity
    ) -> SearchActivity {
        let extractedSources = extractSearchSources(from: object)
        var arguments = fallback.arguments
        arguments.merge(searchActivityArguments(sources: extractedSources)) { _, newValue in newValue }

        return SearchActivity(
            id: fallback.id,
            type: fallback.type,
            status: searchStatusForToolResult(from: object),
            arguments: arguments
        )
    }

    static func searchStatusForToolResult(from object: [String: JSONValue]) -> SearchActivityStatus {
        toolResultIsError(from: object) ? .failed : .completed
    }

    static func toolResultIsError(from object: [String: JSONValue]) -> Bool {
        object.bool(at: ["is_error"]) == true
    }

    static func extractToolResultOutput(from object: [String: JSONValue]) -> String? {
        if let contentOutput = toolResultContentOutput(from: object) {
            return contentOutput
        }

        if let text = normalizedTrimmedString(object.string(at: ["text"])) {
            return text
        }

        if let result = normalizedTrimmedString(object.string(at: ["result"])) {
            return result
        }

        return nil
    }

    static func toolResultContentOutput(from object: [String: JSONValue]) -> String? {
        guard let content = object.array(at: ["content"]) else { return nil }

        let chunks = content.compactMap { value -> String? in
            guard let item = value.objectValue else { return nil }
            return normalizedTrimmedString(item.string(at: ["text"]))
                ?? normalizedTrimmedString(item.string(at: ["url"]))
        }

        return normalizedTrimmedString(chunks.joined(separator: "\n"))
    }
}
