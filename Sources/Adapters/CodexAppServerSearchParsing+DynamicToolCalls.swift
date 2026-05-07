import Collections
import Foundation

extension CodexAppServerAdapter {
    nonisolated static func searchActivityFromDynamicToolCall(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> SearchActivity? {
        guard let toolName = dynamicToolCallName(from: item),
              isLikelyWebSearchTool(named: toolName) else {
            return nil
        }

        let id = dynamicToolCallSearchID(from: item, params: params, fallbackTurnID: fallbackTurnID, toolName: toolName)
        let status = dynamicToolCallSearchStatus(from: item, method: method)
        let arguments = dynamicToolCallSearchArguments(from: item)

        return SearchActivity(
            id: id,
            type: "web_search_call",
            status: status,
            arguments: arguments,
            outputIndex: item.int(at: ["outputIndex"]) ?? params.int(at: ["outputIndex"]),
            sequenceNumber: item.int(at: ["sequenceNumber"]) ?? params.int(at: ["sequenceNumber"])
        )
    }

    private nonisolated static func dynamicToolCallSearchID(
        from item: [String: JSONValue],
        params: [String: JSONValue],
        fallbackTurnID: String?,
        toolName: String
    ) -> String {
        if let explicitID = trimmedValue(
            item.string(at: ["id"])
                ?? item.string(at: ["callId"])
                ?? item.string(at: ["toolCallId"])
                ?? params.string(at: ["itemId"])
        ) {
            return explicitID
        }

        let turnID = trimmedValue(
            params.string(at: ["turnId"])
                ?? params.string(at: ["turn", "id"])
                ?? fallbackTurnID
        ) ?? "unknown_turn"

        var fallbackID = "codex_dynamic_search_\(turnID)_\(toolName.lowercased())"
        if let suffix = toolActivityFallbackSuffix(from: item, params: params) {
            fallbackID += "_\(suffix)"
        }
        return fallbackID
    }

    private nonisolated static func dynamicToolCallSearchStatus(
        from item: [String: JSONValue],
        method: String
    ) -> SearchActivityStatus {
        if method == "item/completed" || method.hasSuffix("/completed") {
            return .completed
        }
        if method.hasSuffix("/failed") {
            return .failed
        }
        if method.hasSuffix("/searching") {
            return .searching
        }
        if method.hasSuffix("/started") {
            return .inProgress
        }

        if let rawStatus = trimmedValue(item.string(at: ["status"]) ?? item.string(at: ["state"])) {
            let normalized = rawStatus
                .replacingOccurrences(
                    of: "([a-z0-9])([A-Z])",
                    with: "$1_$2",
                    options: .regularExpression
                )
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            if normalized == "running" || normalized == "inprogress" || normalized == "in_progress" {
                return .inProgress
            }
            return SearchActivityStatus(rawValue: normalized)
        }
        return .inProgress
    }

    private nonisolated static func dynamicToolCallSearchArguments(from item: [String: JSONValue]) -> [String: AnyCodable] {
        var arguments: [String: AnyCodable] = [:]

        var queriesByKey: OrderedDictionary<String, String> = [:]
        func appendQuery(_ candidate: String?) {
            guard let query = trimmedValue(candidate) else { return }
            let key = query.lowercased()
            guard queriesByKey[key] == nil else { return }
            queriesByKey[key] = query
        }

        appendQuery(item.string(at: ["query"]))
        appendQuery(item.string(at: ["searchQuery"]))
        appendQuery(item.string(at: ["prompt"]))
        appendQuery(item.object(at: ["arguments"])?.string(at: ["query"]))
        appendQuery(item.object(at: ["arguments"])?.string(at: ["searchQuery"]))
        appendQuery(item.object(at: ["input"])?.string(at: ["query"]))
        appendQuery(item.object(at: ["input"])?.string(at: ["searchQuery"]))

        for queryValue in item.array(at: ["queries"]) ?? [] {
            appendQuery(queryValue.stringValue)
        }
        for queryValue in item.object(at: ["arguments"])?.array(at: ["queries"]) ?? [] {
            appendQuery(queryValue.stringValue)
        }
        for queryValue in item.object(at: ["input"])?.array(at: ["queries"]) ?? [] {
            appendQuery(queryValue.stringValue)
        }

        let queryList = Array(queriesByKey.values)
        if let firstQuery = queryList.first {
            arguments["query"] = AnyCodable(firstQuery)
            arguments["queries"] = AnyCodable(queryList)
        }

        var sourcesByURL: OrderedDictionary<String, [String: Any]> = [:]
        func appendSource(url candidateURL: String?, title: String?, snippet: String?) {
            guard let normalizedURL = trimmedValue(candidateURL) else { return }
            let dedupeKey = urlDeduplicationKey(for: normalizedURL)

            var source = sourcesByURL[dedupeKey] ?? ["url": normalizedURL]
            if source["title"] == nil, let title = trimmedValue(title) {
                source["title"] = title
            }
            if source["snippet"] == nil, let snippet = trimmedValue(snippet) {
                source["snippet"] = snippet
            }
            sourcesByURL[dedupeKey] = source
        }

        let sourceCandidatePaths: [[String]] = [
            ["sources"],
            ["result", "sources"],
            ["result", "results"],
            ["output", "sources"],
            ["output", "results"],
            ["searchResult", "sources"],
            ["searchResult", "results"],
            ["webSearch", "sources"],
            ["webSearch", "results"],
            ["arguments", "sources"],
            ["input", "sources"],
        ]

        for path in sourceCandidatePaths {
            for candidate in item.array(at: path) ?? [] {
                guard let object = candidate.objectValue else { continue }
                appendSource(
                    url: object.string(at: ["url"]) ?? object.object(at: ["source"])?.string(at: ["url"]),
                    title: object.string(at: ["title"]) ?? object.object(at: ["source"])?.string(at: ["title"]),
                    snippet: preferredSnippetValue(from: object)
                        ?? object.object(at: ["source"]).flatMap(preferredSnippetValue(from:))
                )
            }
        }

        let allText = collectAgentMessageTextFragments(from: .object(item)).joined(separator: "\n")
        for url in extractURLs(from: allText) {
            appendSource(url: url, title: nil, snippet: nil)
        }

        let sources = Array(sourcesByURL.values)
        if !sources.isEmpty {
            arguments["sources"] = AnyCodable(sources)
            if let first = sources.first {
                if let firstURL = first["url"] as? String {
                    arguments["url"] = AnyCodable(firstURL)
                }
                if let firstTitle = first["title"] as? String {
                    arguments["title"] = AnyCodable(firstTitle)
                }
            }
        }

        return arguments
    }
}
