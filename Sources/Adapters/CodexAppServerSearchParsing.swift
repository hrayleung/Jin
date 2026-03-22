import Collections
import Foundation

// MARK: - Search Activity Parsing

extension CodexAppServerAdapter {

    nonisolated static func searchActivityFromCodexItem(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> SearchActivity? {
        let itemType = item.string(at: ["type"]) ?? ""
        if itemType == "webSearch" {
            return searchActivityFromWebSearchItem(item: item, method: method)
        }
        if itemType == "dynamicToolCall" {
            return searchActivityFromDynamicToolCall(
                item: item,
                method: method,
                params: params,
                fallbackTurnID: fallbackTurnID
            )
        }
        return nil
    }

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

        let id = dynamicToolCallID(from: item, params: params, fallbackTurnID: fallbackTurnID, toolName: toolName)
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

    // MARK: - Web Search Item Parsing

    private nonisolated static func searchActivityFromWebSearchItem(
        item: [String: JSONValue],
        method: String
    ) -> SearchActivity? {
        guard item.string(at: ["type"]) == "webSearch" else { return nil }
        let id = trimmedValue(item.string(at: ["id"])) ?? UUID().uuidString

        var arguments: [String: AnyCodable] = [:]
        var queriesByKey: OrderedDictionary<String, String> = [:]

        func appendQuery(_ raw: String?) {
            guard let query = trimmedValue(raw) else { return }
            let key = query.lowercased()
            guard queriesByKey[key] == nil else { return }
            queriesByKey[key] = query
        }

        appendQuery(item.string(at: ["query"]))
        if let action = item.object(at: ["action"]) {
            appendQuery(action.string(at: ["query"]))
            for queryValue in action.array(at: ["queries"]) ?? [] {
                appendQuery(queryValue.stringValue)
            }
            if let url = trimmedValue(action.string(at: ["url"])) {
                arguments["url"] = AnyCodable(url)
            }
            if let pattern = trimmedValue(action.string(at: ["pattern"])) {
                arguments["pattern"] = AnyCodable(pattern)
            }
            if let actionType = trimmedValue(action.string(at: ["type"])) {
                arguments["action_type"] = AnyCodable(actionType)
            }
        }

        let queryList = Array(queriesByKey.values)
        if let firstQuery = queryList.first {
            arguments["query"] = AnyCodable(firstQuery)
            arguments["queries"] = AnyCodable(queryList)
        }

        let status: SearchActivityStatus
        if method == "item/completed" || method.hasSuffix("/completed") {
            status = .completed
        } else if method.hasSuffix("/failed") {
            status = .failed
        } else {
            status = .searching
        }

        return SearchActivity(
            id: id,
            type: "web_search_call",
            status: status,
            arguments: arguments
        )
    }

    // MARK: - Dynamic Tool Call Search Helpers

    nonisolated static func isLikelyWebSearchTool(named rawName: String) -> Bool {
        let normalized = rawName
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let canonical = normalized.replacingOccurrences(of: ".", with: "_")

        let knownNames: Set<String> = [
            "web_search",
            "websearch",
            "search_web",
            "browser.search",
            "browser_search",
        ]
        if knownNames.contains(normalized) || knownNames.contains(canonical) {
            return true
        }

        let tokens = Set(
            canonical
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )

        if tokens.contains("websearch") {
            return true
        }
        if tokens.contains("browser") && (tokens.contains("search") || tokens.contains("browse")) {
            return true
        }
        if tokens.contains("web") && (tokens.contains("search") || tokens.contains("browse")) {
            return true
        }
        if tokens.contains("search") && tokens.contains("engine") {
            return true
        }
        return false
    }

    private nonisolated static func dynamicToolCallID(
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

    // MARK: - URL Extraction & Snippet Helpers

    nonisolated static func preferredSnippetValue(from object: [String: JSONValue]) -> String? {
        let candidatePaths: [[String]] = [
            ["snippet"],
            ["summary"],
            ["description"],
            ["preview"],
            ["excerpt"],
            ["citedText"],
            ["cited_text"],
            ["quote"],
            ["abstract"],
        ]

        for path in candidatePaths {
            if let value = trimmedValue(object.string(at: path)) {
                return value
            }
        }
        return nil
    }

    nonisolated static func extractURLs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let pattern = #"https?://[^\s<>"'\]\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var resultsByKey: OrderedDictionary<String, String> = [:]
        for match in matches {
            let url = nsText.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\"'"))
            guard !url.isEmpty else { continue }
            let key = urlDeduplicationKey(for: url)
            guard resultsByKey[key] == nil else { continue }
            resultsByKey[key] = url
        }
        return Array(resultsByKey.values)
    }

    nonisolated static func urlDeduplicationKey(for rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL) else {
            return rawURL
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? rawURL
    }
}
