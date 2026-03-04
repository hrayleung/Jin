import Foundation
import Network

// MARK: - Static Parsing & Utility Methods

extension CodexAppServerAdapter {

    // MARK: - Model Info Parsing

    nonisolated static func makeModelInfo(from modelObject: [String: JSONValue]) -> ModelInfo? {
        let modelID = trimmedValue(
            modelObject.string(at: ["id"])
                ?? modelObject.string(at: ["model"])
        )
        guard let modelID else { return nil }

        let displayName = trimmedValue(
            modelObject.string(at: ["displayName"])
                ?? modelObject.string(at: ["model"])
        ) ?? modelID

        var capabilities: ModelCapability = [.streaming]
        if modelObject.contains(inArray: "image", at: ["inputModalities"]) {
            capabilities.insert(.vision)
        }

        let supportedEfforts = parseSupportedReasoningEfforts(from: modelObject)
        var reasoningConfig: ModelReasoningConfig?
        if !supportedEfforts.isEmpty {
            capabilities.insert(.reasoning)
            let defaultEffort = parseReasoningEffort(modelObject.string(at: ["defaultReasoningEffort"]))
                ?? supportedEfforts.first
                ?? .medium
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: defaultEffort)
        }

        let contextWindow = firstPositiveInt(
            from: modelObject,
            candidatePaths: [
                ["contextWindow"],
                ["contextLength"],
                ["context_window"],
                ["context_length"],
            ]
        ) ?? fallbackContextWindow

        let catalogMetadata = parseCatalogMetadata(from: modelObject)

        return ModelInfo(
            id: modelID,
            name: displayName,
            capabilities: capabilities,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            catalogMetadata: catalogMetadata
        )
    }

    // MARK: - Dynamic Tool Call Output

    nonisolated static func parseDynamicToolCallOutputParts(
        from item: [String: JSONValue]
    ) -> [ContentPart] {
        guard let contentItems = item.array(at: ["contentItems"]), !contentItems.isEmpty else {
            return []
        }

        var parts: [ContentPart] = []
        parts.reserveCapacity(contentItems.count)

        for contentItem in contentItems {
            guard let object = contentItem.objectValue else { continue }
            let type = object.string(at: ["type"])?.lowercased()
            switch type {
            case "inputtext", "input_text":
                if let text = trimmedValue(object.string(at: ["text"])), !text.isEmpty {
                    parts.append(.text(text))
                }
            case "inputimage", "input_image":
                let rawURL = trimmedValue(object.string(at: ["imageUrl"]) ?? object.string(at: ["image_url"]))
                if let rawURL, let url = URL(string: rawURL) {
                    parts.append(.image(ImageContent(mimeType: "image/png", url: url)))
                }
            default:
                break
            }
        }

        return parts
    }

    // MARK: - Search Activity Parsing

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

    // MARK: - Codex Tool Activity Parsing

    nonisolated static func codexToolActivityFromDynamicToolCall(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        guard let toolName = dynamicToolCallName(from: item) else {
            return nil
        }
        guard !isLikelyWebSearchTool(named: toolName) else {
            return nil
        }

        let id = codexToolActivityID(from: item, params: params, fallbackTurnID: fallbackTurnID, toolName: toolName)
        let status = codexToolActivityStatus(from: item, method: method)
        let arguments = codexToolActivityArguments(from: item)
        let output = codexToolActivityOutput(from: item)

        return CodexToolActivity(
            id: id,
            toolName: toolName,
            status: status,
            arguments: arguments,
            output: output
        )
    }

    nonisolated static func codexToolActivityFromCodexItem(
        item: [String: JSONValue],
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        let itemType = item.string(at: ["type"]) ?? ""

        let nonToolTypes: Set<String> = [
            "webSearch",
            "agentMessage",
            "reasoning",
            "enteredReviewMode",
            "exitedReviewMode",
            "contextCompaction",
            "",
        ]
        if nonToolTypes.contains(itemType) {
            return nil
        }

        if itemType == "dynamicToolCall" {
            return codexToolActivityFromDynamicToolCall(
                item: item,
                method: method,
                params: params,
                fallbackTurnID: fallbackTurnID
            )
        }

        return codexToolActivityFromGenericItem(
            item: item,
            itemType: itemType,
            method: method,
            params: params,
            fallbackTurnID: fallbackTurnID
        )
    }

    // MARK: - Agent Message Text

    nonisolated static func parseAgentMessageText(from item: [String: JSONValue]) -> String? {
        let root = JSONValue.object(item)
        let collected = collectAgentMessageTextFragments(from: root)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collected.isEmpty ? nil : collected
    }

    nonisolated static func assistantTextSuffix(fromSnapshot snapshot: String, emitted: String) -> String? {
        guard !snapshot.isEmpty else { return nil }
        if emitted.isEmpty {
            return snapshot
        }
        if snapshot == emitted {
            return nil
        }
        if snapshot.hasPrefix(emitted) {
            let index = snapshot.index(snapshot.startIndex, offsetBy: emitted.count)
            let suffix = String(snapshot[index...])
            return suffix.isEmpty ? nil : suffix
        }
        if emitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snapshot
        }
        return nil
    }

    // MARK: - Connectivity Error Handling

    nonisolated static func remapCodexConnectivityError(_ error: Error, endpoint: URL) -> Error {
        guard let guidance = codexConnectivityGuidanceMessage(for: error, endpoint: endpoint) else {
            return error
        }
        return LLMError.providerError(code: "codex_server_unavailable", message: guidance)
    }

    nonisolated static func codexConnectivityGuidanceMessage(
        for error: Error,
        endpoint: URL
    ) -> String? {
        guard isLikelyCodexServerUnavailable(error) else { return nil }
        let endpointString = endpoint.absoluteString
        return """
        Cannot connect to Codex App Server at \(endpointString).

        If you're using a local server, start it first:
        - Jin -> Settings -> Providers -> Codex App Server (Beta) -> Start Server
        - Terminal: codex app-server --listen \(endpointString)

        If you're using a remote endpoint, verify the URL/network and retry.
        """
    }

    // MARK: - Private Helpers

    private nonisolated static func searchActivityFromWebSearchItem(
        item: [String: JSONValue],
        method: String
    ) -> SearchActivity? {
        guard item.string(at: ["type"]) == "webSearch" else { return nil }
        let id = trimmedValue(item.string(at: ["id"])) ?? UUID().uuidString

        var arguments: [String: AnyCodable] = [:]
        var queries: [String] = []
        var seenQueries = Set<String>()

        func appendQuery(_ raw: String?) {
            guard let query = trimmedValue(raw) else { return }
            let key = query.lowercased()
            guard seenQueries.insert(key).inserted else { return }
            queries.append(query)
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

        if let firstQuery = queries.first {
            arguments["query"] = AnyCodable(firstQuery)
            arguments["queries"] = AnyCodable(queries)
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

    private nonisolated static func codexToolActivityFromGenericItem(
        item: [String: JSONValue],
        itemType: String,
        method: String,
        params: [String: JSONValue],
        fallbackTurnID: String?
    ) -> CodexToolActivity? {
        let id = codexToolActivityID(
            from: item,
            params: params,
            fallbackTurnID: fallbackTurnID,
            toolName: itemType
        )

        let toolName = genericItemToolName(item: item, itemType: itemType)
        let status = codexToolActivityStatus(from: item, method: method)
        let arguments = genericItemArguments(item: item, itemType: itemType)
        let output = genericItemOutput(item: item, itemType: itemType)

        return CodexToolActivity(
            id: id,
            toolName: toolName,
            status: status,
            arguments: arguments,
            output: output
        )
    }

    private nonisolated static func genericItemToolName(
        item: [String: JSONValue],
        itemType: String
    ) -> String {
        switch itemType {
        case "commandExecution":
            return trimmedValue(item.string(at: ["command"]))
                .map { cmd in
                    let first = cmd.components(separatedBy: .whitespaces).first ?? cmd
                    return first.count > 40 ? String(first.prefix(37)) + "..." : first
                }
                ?? "shell"
        case "fileChange":
            if let changes = item.array(at: ["changes"]),
               let firstPath = changes.first?.objectValue?.string(at: ["path"]) {
                let filename = (firstPath as NSString).lastPathComponent
                let kind = changes.first?.objectValue?.string(at: ["kind"]) ?? "edit"
                return "\(kind): \(filename)"
            }
            return "file change"
        case "mcpToolCall":
            if let server = trimmedValue(item.string(at: ["server"])),
               let tool = trimmedValue(item.string(at: ["tool"])) {
                return "\(server)/\(tool)"
            }
            return trimmedValue(item.string(at: ["tool"])) ?? "mcp tool"
        case "collabToolCall":
            return trimmedValue(item.string(at: ["tool"])) ?? "collab tool"
        case "imageView":
            return "image view"
        default:
            return trimmedValue(
                item.string(at: ["tool"])
                    ?? item.string(at: ["name"])
                    ?? item.string(at: ["tool", "name"])
            ) ?? itemType
        }
    }

    private nonisolated static func genericItemArguments(
        item: [String: JSONValue],
        itemType: String
    ) -> [String: AnyCodable] {
        var arguments: [String: AnyCodable] = [:]

        switch itemType {
        case "commandExecution":
            if let command = trimmedValue(item.string(at: ["command"])) {
                arguments["command"] = AnyCodable(command)
            }
            if let cwd = trimmedValue(item.string(at: ["cwd"])) {
                arguments["cwd"] = AnyCodable(cwd)
            }
            if let exitCode = item.int(at: ["exitCode"]) {
                arguments["exitCode"] = AnyCodable(exitCode)
            }

        case "fileChange":
            if let changes = item.array(at: ["changes"]) {
                var paths: [String] = []
                for change in changes {
                    if let obj = change.objectValue,
                       let path = trimmedValue(obj.string(at: ["path"])) {
                        paths.append(path)
                    }
                }
                if !paths.isEmpty {
                    arguments["paths"] = AnyCodable(paths)
                }
            }

        case "mcpToolCall":
            if let server = trimmedValue(item.string(at: ["server"])) {
                arguments["server"] = AnyCodable(server)
            }
            if let tool = trimmedValue(item.string(at: ["tool"])) {
                arguments["tool"] = AnyCodable(tool)
            }
            if let argsObj = item.object(at: ["arguments"]) {
                for (key, value) in argsObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            }

        case "collabToolCall":
            if let tool = trimmedValue(item.string(at: ["tool"])) {
                arguments["tool"] = AnyCodable(tool)
            }
            if let prompt = trimmedValue(item.string(at: ["prompt"])) {
                arguments["prompt"] = AnyCodable(prompt)
            }

        case "imageView":
            if let path = trimmedValue(item.string(at: ["path"])) {
                arguments["path"] = AnyCodable(path)
            }

        default:
            if let argsObj = item.object(at: ["arguments"]) {
                for (key, value) in argsObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            } else if let inputObj = item.object(at: ["input"]) {
                for (key, value) in inputObj {
                    arguments[key] = AnyCodable(jsonValueToAny(value))
                }
            }
            for key in ["command", "path", "file", "tool", "query"] {
                if arguments[key] == nil, let value = item.string(at: [key]) {
                    arguments[key] = AnyCodable(value)
                }
            }
        }

        return arguments
    }

    private nonisolated static func genericItemOutput(
        item: [String: JSONValue],
        itemType: String
    ) -> String? {
        switch itemType {
        case "commandExecution":
            return trimmedValue(item.string(at: ["aggregatedOutput"]))
                ?? trimmedValue(item.string(at: ["output"]))
        case "fileChange":
            return nil
        case "mcpToolCall":
            return trimmedValue(item.string(at: ["result"]))
                ?? trimmedValue(item.string(at: ["error"]))
        default:
            return codexToolActivityOutput(from: item)
        }
    }

    private nonisolated static func codexToolActivityID(
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

        var fallbackID = "codex_tool_\(turnID)_\(toolName.lowercased())"
        if let suffix = toolActivityFallbackSuffix(from: item, params: params) {
            fallbackID += "_\(suffix)"
        }
        return fallbackID
    }

    private nonisolated static func codexToolActivityStatus(
        from item: [String: JSONValue],
        method: String
    ) -> CodexToolActivityStatus {
        if method == "item/completed" || method.hasSuffix("/completed") {
            return .completed
        }
        if method.hasSuffix("/failed") {
            return .failed
        }
        if method.hasSuffix("/started") || method == "item/started" {
            return .running
        }
        if method.hasSuffix("/outputDelta") || method.hasSuffix("/requestApproval") {
            return .running
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
            if normalized == "in_progress" || normalized == "inprogress" {
                return .running
            }
            if normalized == "declined" {
                return .failed
            }
            return CodexToolActivityStatus(rawValue: normalized)
        }
        return .running
    }

    private nonisolated static func codexToolActivityArguments(from item: [String: JSONValue]) -> [String: AnyCodable] {
        var arguments: [String: AnyCodable] = [:]

        if let argsObj = item.object(at: ["arguments"]) {
            for (key, value) in argsObj {
                arguments[key] = AnyCodable(jsonValueToAny(value))
            }
        } else if let inputObj = item.object(at: ["input"]) {
            for (key, value) in inputObj {
                arguments[key] = AnyCodable(jsonValueToAny(value))
            }
        }

        for key in ["command", "cmd", "path", "file", "filePath", "file_path", "query", "content"] {
            if arguments[key] == nil, let value = item.string(at: [key]) {
                arguments[key] = AnyCodable(value)
            }
        }

        return arguments
    }

    nonisolated static func jsonValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .number(let n):
            return n
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { jsonValueToAny($0) }
        case .object(let obj):
            return obj.mapValues { jsonValueToAny($0) }
        }
    }

    private nonisolated static func codexToolActivityOutput(from item: [String: JSONValue]) -> String? {
        if let output = trimmedValue(item.string(at: ["output"])) {
            return output
        }
        if let result = trimmedValue(item.string(at: ["result"])) {
            return result
        }
        if let outputText = trimmedValue(item.string(at: ["output", "text"])) {
            return outputText
        }
        return nil
    }

    private nonisolated static func collectAgentMessageTextFragments(from value: JSONValue) -> [String] {
        switch value {
        case .string(let text):
            return [text]

        case .array(let array):
            return array.flatMap { collectAgentMessageTextFragments(from: $0) }

        case .object(let object):
            var fragments: [String] = []

            if let text = object.string(at: ["text"]) {
                fragments.append(text)
            }
            if let valueText = object.string(at: ["value"]),
               object.string(at: ["type"]) == "output_text" || object.string(at: ["type"]) == "text" {
                fragments.append(valueText)
            }

            for key in ["message", "content", "contentItems", "output", "parts", "item"] {
                guard let nested = object[key] else { continue }
                fragments.append(contentsOf: collectAgentMessageTextFragments(from: nested))
            }
            return fragments

        default:
            return []
        }
    }

    private nonisolated static func dynamicToolCallName(from item: [String: JSONValue]) -> String? {
        trimmedValue(
            item.string(at: ["name"])
                ?? item.string(at: ["toolName"])
                ?? item.string(at: ["tool"])
                ?? item.string(at: ["tool", "name"])
                ?? item.string(at: ["tool", "id"])
                ?? item.string(at: ["tool", "type"])
                ?? item.string(at: ["kind"])
        )
    }

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

    private nonisolated static func toolActivityFallbackSuffix(
        from item: [String: JSONValue],
        params: [String: JSONValue]
    ) -> String? {
        if let sequence = item.int(at: ["sequenceNumber"]) ?? params.int(at: ["sequenceNumber"]) {
            return "seq\(sequence)"
        }
        if let outputIndex = item.int(at: ["outputIndex"]) ?? params.int(at: ["outputIndex"]) {
            return "out\(outputIndex)"
        }
        if let callIndex = item.int(at: ["callIndex"])
            ?? params.int(at: ["callIndex"])
            ?? item.int(at: ["index"])
            ?? params.int(at: ["index"]) {
            return "idx\(callIndex)"
        }
        return nil
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

        var queries: [String] = []
        var seenQueries = Set<String>()
        func appendQuery(_ candidate: String?) {
            guard let query = trimmedValue(candidate) else { return }
            let key = query.lowercased()
            guard seenQueries.insert(key).inserted else { return }
            queries.append(query)
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

        if let firstQuery = queries.first {
            arguments["query"] = AnyCodable(firstQuery)
            arguments["queries"] = AnyCodable(queries)
        }

        var sources: [[String: Any]] = []
        var seenURLs = Set<String>()
        func appendSource(url candidateURL: String?, title: String?, snippet: String?) {
            guard let normalizedURL = trimmedValue(candidateURL) else { return }
            let dedupeKey = normalizedURL.lowercased()
            guard seenURLs.insert(dedupeKey).inserted else { return }

            var source: [String: Any] = ["url": normalizedURL]
            if let title = trimmedValue(title) {
                source["title"] = title
            }
            if let snippet = trimmedValue(snippet) {
                source["snippet"] = snippet
            }
            sources.append(source)
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

    private nonisolated static func preferredSnippetValue(from object: [String: JSONValue]) -> String? {
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

    private nonisolated static func extractURLs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let pattern = #"https?://[^\s<>"'\]\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var results: [String] = []
        var seen = Set<String>()
        for match in matches {
            let url = nsText.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\"'"))
            guard !url.isEmpty else { continue }
            let key = url.lowercased()
            guard seen.insert(key).inserted else { continue }
            results.append(url)
        }
        return results
    }

    private nonisolated static func parseCatalogMetadata(from modelObject: [String: JSONValue]) -> ModelCatalogMetadata? {
        let availabilityMessage = trimmedValue(modelObject.string(at: ["availabilityNux", "message"]))
        let upgradeTarget = trimmedValue(
            modelObject.string(at: ["upgradeInfo", "model"])
                ?? modelObject.string(at: ["upgrade"])
        )
        let upgradeMessage = trimmedValue(
            modelObject.string(at: ["upgradeInfo", "upgradeCopy"])
                ?? modelObject.string(at: ["upgradeCopy"])
        )

        let metadata = ModelCatalogMetadata(
            availabilityMessage: availabilityMessage,
            upgradeTargetModelID: upgradeTarget,
            upgradeMessage: upgradeMessage
        )
        return metadata.isEmpty ? nil : metadata
    }

    private nonisolated static func parseSupportedReasoningEfforts(from modelObject: [String: JSONValue]) -> [ReasoningEffort] {
        guard let supported = modelObject.array(at: ["supportedReasoningEfforts"]) else {
            return []
        }

        var efforts: [ReasoningEffort] = []
        for item in supported {
            if let effort = parseReasoningEffort(item.stringValue) {
                efforts.append(effort)
                continue
            }

            if let object = item.objectValue {
                let value = object.string(at: ["reasoningEffort"]) ?? object.string(at: ["effort"])
                if let effort = parseReasoningEffort(value) {
                    efforts.append(effort)
                }
            }
        }

        var seen = Set<ReasoningEffort>()
        return efforts.filter { seen.insert($0).inserted }
    }

    private nonisolated static func parseReasoningEffort(_ raw: String?) -> ReasoningEffort? {
        guard let raw else { return nil }
        return ReasoningEffort(rawValue: raw.lowercased())
    }

    nonisolated static func firstPositiveInt(
        from object: [String: JSONValue],
        candidatePaths: [[String]]
    ) -> Int? {
        for path in candidatePaths {
            if let value = object.int(at: path), value > 0 {
                return value
            }
        }
        return nil
    }

    nonisolated static func trimmedValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func isLikelyCodexServerUnavailable(_ error: Error) -> Bool {
        if case LLMError.invalidRequest(let message) = error,
           message.localizedCaseInsensitiveContains("not connected") {
            return true
        }

        guard case LLMError.networkError(let underlying) = error else {
            return false
        }

        if isLikelyConnectionPOSIXError(underlying) {
            return true
        }

        let description = underlying.localizedDescription.lowercased()
        let connectivityHints = [
            "connection refused",
            "failed to connect",
            "timed out",
            "network is unreachable",
            "host is down",
            "socket is not connected",
            "websocket connection was cancelled",
            "connection reset",
            "connection aborted",
            "broken pipe",
        ]
        return connectivityHints.contains { description.contains($0) }
    }

    private nonisolated static func isLikelyConnectionPOSIXError(_ error: Error) -> Bool {
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let code):
                return isLikelyConnectionPOSIXCode(Int32(code.rawValue))
            case .dns:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return isLikelyConnectionPOSIXCode(Int32(nsError.code))
        }
        return false
    }

    private nonisolated static func isLikelyConnectionPOSIXCode(_ code: Int32) -> Bool {
        code == ECONNREFUSED
            || code == ETIMEDOUT
            || code == EHOSTUNREACH
            || code == ENETUNREACH
            || code == EHOSTDOWN
            || code == ECONNRESET
            || code == ECONNABORTED
            || code == EPIPE
    }
}
