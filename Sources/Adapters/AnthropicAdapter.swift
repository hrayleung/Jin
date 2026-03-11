import Foundation

actor AnthropicAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .promptCaching]

    private let networkManager: NetworkManager
    private let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentMessageID: String?
                    var currentBlockIndex: Int?
                    var currentToolUse: AnthropicToolCallBuilder?
                    var currentServerToolUse: AnthropicSearchActivityBuilder?
                    var currentCodeExecutionID: String?
                    var currentCodeExecutionCode: String = ""
                    var currentContentBlockType: String?
                    var currentThinkingSignature: String?
                    var usageAccumulator = AnthropicUsageAccumulator()

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            do {
                                if let streamEvent = try parseJSONLine(
                                    data,
                                    currentMessageID: &currentMessageID,
                                    currentBlockIndex: &currentBlockIndex,
                                    currentToolUse: &currentToolUse,
                                    currentServerToolUse: &currentServerToolUse,
                                    currentCodeExecutionID: &currentCodeExecutionID,
                                    currentCodeExecutionCode: &currentCodeExecutionCode,
                                    currentContentBlockType: &currentContentBlockType,
                                    currentThinkingSignature: &currentThinkingSignature,
                                    usageAccumulator: &usageAccumulator
                                ) {
                                    continuation.yield(streamEvent)
                                }
                            } catch is DecodingError {
                                // Be resilient to provider-side schema drift in individual events.
                                // Skip malformed events instead of aborting the whole response stream.
                                continue
                            } catch is LLMError {
                                // Malformed tool call arguments or similar event-level issue.
                                // Skip the broken event rather than killing the entire stream.
                                continue
                            }
                        case .done:
                            continuation.yield(.messageEnd(usage: usageAccumulator.toUsage()))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL("\(baseURL)/models"),
            headers: anthropicHeaders(apiKey: key)
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var allModels: [ModelInfo] = []
        var afterID: String?
        var seenIDs: Set<String> = []

        while true {
            var components = URLComponents(string: "\(baseURL)/models")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "100")
            ]
            if let afterID {
                queryItems.append(URLQueryItem(name: "after_id", value: afterID))
            }
            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw LLMError.invalidRequest(message: "Invalid Anthropic models URL")
            }

            let request = NetworkRequestFactory.makeRequest(
                url: url,
                headers: anthropicHeaders(apiKey: apiKey)
            )

            let (data, _) = try await networkManager.sendRequest(request)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(AnthropicModelsListResponse.self, from: data)

            for model in response.data {
                guard !seenIDs.contains(model.id) else { continue }
                seenIDs.insert(model.id)
                allModels.append(makeModelInfo(from: model))
            }

            guard response.hasMore == true,
                  let lastID = response.lastID,
                  !lastID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  lastID != afterID else {
                break
            }

            afterID = lastID
        }

        return allModels.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        return tools.map(translateSingleTool)
    }

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        let properties = translateProperties(tool.parameters.properties)

        return [
            "name": tool.name,
            "description": tool.description,
            "input_schema": [
                "type": tool.parameters.type,
                "properties": properties,
                "required": tool.parameters.required
            ]
        ]
    }

    private func translateProperties(_ properties: [String: PropertySchema]) -> [String: Any] {
        properties.mapValues { $0.toDictionary() }
    }

    // MARK: - Private

    private var baseURL: String {
        providerConfig.baseURL ?? "https://api.anthropic.com/v1"
    }

    private var anthropicVersion: String {
        "2023-06-01"
    }

    private func anthropicHeaders(apiKey: String, contentType: String? = nil, betaHeader: String? = nil) -> [String: String] {
        var headers: [String: String] = [
            "x-api-key": apiKey,
            "anthropic-version": anthropicVersion
        ]

        if let contentType {
            headers["Content-Type"] = contentType
        }
        if let betaHeader {
            headers["anthropic-beta"] = betaHeader
        }

        return headers
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        // Native PDF is supported on Claude 4.x models.
        let lower = modelID.lowercased()
        return lower.contains("-4-") || lower.contains("-4.")
    }

    private func supportsAdaptiveThinking(_ modelID: String) -> Bool {
        AnthropicModelLimits.supportsAdaptiveThinking(for: modelID)
    }

    private func supportsEffort(_ modelID: String) -> Bool {
        AnthropicModelLimits.supportsEffort(for: modelID)
    }

    private func supportsMaxEffort(_ modelID: String) -> Bool {
        AnthropicModelLimits.supportsMaxEffort(for: modelID)
    }

    private func supportsWebSearch(_ modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    private func supportsWebSearchDynamicFiltering(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
            for: providerConfig.type,
            modelID: modelID
        )
    }

    private func mapAnthropicEffort(_ effort: ReasoningEffort, modelID: String) -> String {
        switch effort {
        case .none:
            return "high"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return supportsMaxEffort(modelID) ? "max" : "high"
        }
    }

    private func defaultAnthropicEffort(for modelID: String) -> ReasoningEffort {
        let lower = modelID.lowercased()
        if lower == "claude-sonnet-4-6" || lower.contains("claude-sonnet-4-6-") {
            return .medium
        }
        return .high
    }

    private func providerSpecificJSONDictionary(_ value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let codableDictionary = value as? [String: AnyCodable] {
            return codableDictionary.mapValues { $0.value }
        }
        return nil
    }

    private func providerSpecificStringArray(_ value: Any) -> [String]? {
        if let strings = value as? [String] {
            return strings
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }
        }
        return nil
    }

    private func normalizeAnthropicProviderSpecificTools(_ value: Any, modelID: String) -> Any {
        guard let tools = value as? [Any] else { return value }

        var normalized: [Any] = []
        normalized.reserveCapacity(tools.count)

        for item in tools {
            guard var dict = item as? [String: Any],
                  let type = dict["type"] as? String else {
                normalized.append(item)
                continue
            }

            if type == "web_search_20250305" || type == "web_search_20260209" {
                let useDynamicFiltering = (type == "web_search_20260209") && supportsWebSearchDynamicFiltering(modelID)
                dict["type"] = useDynamicFiltering ? "web_search_20260209" : "web_search_20250305"

                if let maxUses = dict["max_uses"] as? Int, maxUses <= 0 {
                    dict.removeValue(forKey: "max_uses")
                }

                let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(
                    providerSpecificStringArray(dict["allowed_domains"] as Any)
                )
                let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(
                    providerSpecificStringArray(dict["blocked_domains"] as Any)
                )

                if !allowed.isEmpty {
                    dict["allowed_domains"] = allowed
                    dict.removeValue(forKey: "blocked_domains")
                } else if !blocked.isEmpty {
                    dict["blocked_domains"] = blocked
                    dict.removeValue(forKey: "allowed_domains")
                } else {
                    dict.removeValue(forKey: "allowed_domains")
                    dict.removeValue(forKey: "blocked_domains")
                }
            }

            normalized.append(dict)
        }

        return normalized
    }

    private func extractAnthropicBetaHeader(from controls: GenerationControls) -> String? {
        let keys = ["anthropic_beta", "anthropic-beta"]
        for key in keys {
            guard let rawValue = controls.providerSpecific[key]?.value else { continue }

            if let string = rawValue as? String {
                let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }

            if let values = providerSpecificStringArray(rawValue) {
                let joined = values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ",")
                if !joined.isEmpty {
                    return joined
                }
            }
        }

        return nil
    }

    private func mergeOutputConfig(into body: inout [String: Any], additional: [String: Any]) {
        guard !additional.isEmpty else { return }
        var merged = (body["output_config"] as? [String: Any]) ?? [:]
        for (key, value) in additional {
            merged[key] = value
        }
        body["output_config"] = merged
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let normalizedMessages = AnthropicToolUseNormalizer.normalize(messages)
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let supportsNativePDF = allowNativePDF && self.supportsNativePDF(modelID)
        let cacheStrategy = controls.contextCache?.strategy ?? .systemOnly
        let blockCacheControl = anthropicBlockCacheControl(
            from: controls.contextCache,
            strategy: cacheStrategy
        )
        let topLevelCacheControl = anthropicTopLevelCacheControl(
            from: controls.contextCache,
            strategy: cacheStrategy
        )

        let betaHeader = extractAnthropicBetaHeader(from: controls)

        let nonSystemMessages = normalizedMessages.filter { $0.role != .system }
        var translatedMessages: [[String: Any]] = []
        translatedMessages.reserveCapacity(nonSystemMessages.count)
        for message in nonSystemMessages {
            let translated = try translateMessage(
                message,
                supportsNativePDF: supportsNativePDF,
                cacheControl: blockCacheControl,
                cacheStrategy: cacheStrategy
            )
            translatedMessages.append(translated)
        }

        try AnthropicRequestPreflight.validate(messages: translatedMessages)

        let resolvedMaxTokens = AnthropicModelLimits.resolvedMaxTokens(
            requested: controls.maxTokens,
            for: modelID,
            fallback: 4096
        )

        var body: [String: Any] = [
            "model": modelID,
            "messages": translatedMessages,
            "max_tokens": resolvedMaxTokens,
            "stream": streaming
        ]

        appendSystemPrompt(to: &body, from: normalizedMessages, cacheControl: blockCacheControl)
        if let topLevelCacheControl {
            body["cache_control"] = topLevelCacheControl
        }
        appendThinkingConfig(to: &body, controls: controls, modelID: modelID)
        appendToolSpecs(to: &body, controls: controls, tools: tools, modelID: modelID)
        applyProviderSpecificOverrides(to: &body, controls: controls, modelID: modelID)

        return try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL("\(baseURL)/messages"),
            headers: anthropicHeaders(apiKey: apiKey, betaHeader: betaHeader),
            body: body
        )
    }

    private func appendSystemPrompt(to body: inout [String: Any], from messages: [Message], cacheControl: [String: Any]?) {
        guard let systemPrompt = messages.first(where: { $0.role == .system })?.content.first,
              case .text(let text) = systemPrompt else {
            return
        }
        var block: [String: Any] = [
            "type": "text",
            "text": text
        ]
        if let cacheControl {
            block["cache_control"] = cacheControl
        }
        body["system"] = [block]
    }

    private func appendThinkingConfig(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        let thinkingEnabled = controls.reasoning?.enabled == true
        let providerSpecificHasThinking = controls.providerSpecific["thinking"] != nil

        if !thinkingEnabled {
            if let temperature = controls.temperature {
                body["temperature"] = temperature
            }
            if let topP = controls.topP {
                body["top_p"] = topP
            }
            return
        }

        if !providerSpecificHasThinking {
            if supportsAdaptiveThinking(modelID) {
                // 4.6 models: always adaptive. budget_tokens is deprecated.
                body["thinking"] = ["type": "adaptive"]
            } else {
                body["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": controls.reasoning?.budgetTokens ?? 2048
                ]
            }
        }

        if supportsEffort(modelID),
           let effort = controls.reasoning?.effort,
           effort != .none {
            mergeOutputConfig(
                into: &body,
                additional: ["effort": mapAnthropicEffort(effort, modelID: modelID)]
            )
        }
    }

    private func appendToolSpecs(to body: inout [String: Any], controls: GenerationControls, tools: [ToolDefinition], modelID: String) {
        var toolSpecs: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
            toolSpecs.append(buildWebSearchToolSpec(controls: controls, modelID: modelID))
        }

        if controls.codeExecution?.enabled == true {
            toolSpecs.append([
                "type": "code_execution_20250825",
                "name": "code_execution"
            ])
        }

        if !tools.isEmpty, let customTools = translateTools(tools) as? [[String: Any]] {
            toolSpecs.append(contentsOf: customTools)
        }

        if !toolSpecs.isEmpty {
            body["tools"] = toolSpecs
        }
    }

    private func buildWebSearchToolSpec(controls: GenerationControls, modelID: String) -> [String: Any] {
        let ws = controls.webSearch!
        let useDynamicFiltering = (ws.dynamicFiltering == true) && supportsWebSearchDynamicFiltering(modelID)

        let allowedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(ws.allowedDomains)
        let blockedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(ws.blockedDomains)

        var spec: [String: Any] = [
            "type": useDynamicFiltering ? "web_search_20260209" : "web_search_20250305",
            "name": "web_search"
        ]
        if let maxUses = ws.maxUses, maxUses > 0 {
            spec["max_uses"] = maxUses
        }
        if !allowedDomains.isEmpty {
            spec["allowed_domains"] = allowedDomains
        } else if !blockedDomains.isEmpty {
            spec["blocked_domains"] = blockedDomains
        }
        if let loc = ws.userLocation, !loc.isEmpty {
            spec["user_location"] = buildUserLocationDict(loc)
        }
        return spec
    }

    private func buildUserLocationDict(_ loc: WebSearchUserLocation) -> [String: Any] {
        var locDict: [String: Any] = ["type": "approximate"]
        if let city = loc.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            locDict["city"] = city
        }
        if let region = loc.region?.trimmingCharacters(in: .whitespacesAndNewlines), !region.isEmpty {
            locDict["region"] = region
        }
        if let country = loc.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
            locDict["country"] = country
        }
        if let tz = loc.timezone?.trimmingCharacters(in: .whitespacesAndNewlines), !tz.isEmpty {
            locDict["timezone"] = tz
        }
        return locDict
    }

    private func applyProviderSpecificOverrides(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        for (key, value) in controls.providerSpecific {
            if key == "anthropic_beta" || key == "anthropic-beta" {
                continue
            }

            if key == "tools" {
                body[key] = normalizeAnthropicProviderSpecificTools(value.value, modelID: modelID)
                continue
            }

            if key == "output_format" {
                mergeOutputConfig(into: &body, additional: ["format": value.value])
                continue
            }

            if key == "output_config", let dict = providerSpecificJSONDictionary(value.value) {
                mergeOutputConfig(into: &body, additional: dict)
                continue
            }

            body[key] = value.value
        }
    }

    private func translateMessage(
        _ message: Message,
        supportsNativePDF: Bool,
        cacheControl: [String: Any]?,
        cacheStrategy: ContextCacheStrategy
    ) throws -> [String: Any] {
        var content: [[String: Any]] = []

        func maybeApplyCache(to block: inout [String: Any]) {
            guard let cacheControl, message.role != .assistant else { return }
            switch cacheStrategy {
            case .systemOnly:
                return
            case .systemAndTools:
                block["cache_control"] = cacheControl
            case .prefixWindow:
                // Prefix-window uses top-level Anthropic automatic caching.
                return
            }
        }

        appendToolResultBlocks(from: message, to: &content, applyCache: maybeApplyCache)
        appendThinkingBlocks(from: message, to: &content)
        try appendUserFacingBlocks(from: message, supportsNativePDF: supportsNativePDF, to: &content, applyCache: maybeApplyCache)
        appendToolUseBlocks(from: message, to: &content)

        return [
            "role": message.role == .assistant ? "assistant" : "user",
            "content": content
        ]
    }

    private func appendToolResultBlocks(
        from message: Message,
        to content: inout [[String: Any]],
        applyCache: (inout [String: Any]) -> Void
    ) {
        guard let toolResults = message.toolResults else { return }
        for result in toolResults {
            let trimmed = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeContent = trimmed.isEmpty ? "<empty_content>" : result.content

            var block: [String: Any] = [
                "type": "tool_result",
                "tool_use_id": result.toolCallID,
                "content": safeContent,
                "is_error": result.isError
            ]
            applyCache(&block)
            content.append(block)
        }
    }

    private func appendThinkingBlocks(from message: Message, to content: inout [[String: Any]]) {
        guard message.role == .assistant else { return }
        for part in message.content {
            switch part {
            case .thinking(let thinking):
                // Only send thinking blocks that originated from Anthropic.
                // Blocks from other providers (Gemini, OpenAI, etc.) have foreign signatures
                // or nil signatures that would cause a 400 error from Anthropic.
                // Blocks with provider == nil are from pre-tagging persisted data — skip them
                // since we cannot verify their origin.
                guard thinking.provider == ProviderType.anthropic.rawValue,
                      let signature = thinking.signature,
                      !signature.isEmpty else {
                    continue
                }
                content.append([
                    "type": "thinking",
                    "thinking": thinking.text,
                    "signature": signature
                ])
            case .redactedThinking(let redacted):
                guard redacted.provider == ProviderType.anthropic.rawValue,
                      !redacted.data.isEmpty else {
                    continue
                }
                content.append([
                    "type": "redacted_thinking",
                    "data": redacted.data
                ])
            default:
                break
            }
        }
    }

    private func appendUserFacingBlocks(
        from message: Message,
        supportsNativePDF: Bool,
        to content: inout [[String: Any]],
        applyCache: (inout [String: Any]) -> Void
    ) throws {
        guard message.role != .tool else { return }
        for part in message.content {
            switch part {
            case .text(let text):
                var block: [String: Any] = ["type": "text", "text": text]
                applyCache(&block)
                content.append(block)
            case .image(let image):
                if let imageBlock = try translateImageBlock(image) {
                    content.append(imageBlock)
                }
            case .file(let file):
                try translateFileBlock(file, supportsNativePDF: supportsNativePDF, to: &content, applyCache: applyCache)
            case .video(let video):
                var block: [String: Any] = [
                    "type": "text",
                    "text": unsupportedVideoInputNotice(video, providerName: "Anthropic", apiName: "Messages API")
                ]
                applyCache(&block)
                content.append(block)
            default:
                break
            }
        }
    }

    private func translateImageBlock(_ image: ImageContent) throws -> [String: Any]? {
        let data: Data?
        if let existing = image.data {
            data = existing
        } else if let url = image.url, url.isFileURL {
            data = try resolveFileData(from: url)
        } else {
            data = nil
        }
        guard let data else { return nil }
        return [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": image.mimeType,
                "data": data.base64EncodedString()
            ]
        ]
    }

    private func translateFileBlock(
        _ file: FileContent,
        supportsNativePDF: Bool,
        to content: inout [[String: Any]],
        applyCache: (inout [String: Any]) -> Void
    ) throws {
        if supportsNativePDF && file.mimeType == "application/pdf" {
            let pdfData: Data?
            if let data = file.data {
                pdfData = data
            } else if let url = file.url, url.isFileURL {
                pdfData = try resolveFileData(from: url)
            } else {
                pdfData = nil
            }

            if let pdfData {
                var block: [String: Any] = [
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": pdfData.base64EncodedString()
                    ]
                ]
                applyCache(&block)
                content.append(block)
                return
            }
        }

        let text = AttachmentPromptRenderer.fallbackText(for: file)
        var block: [String: Any] = ["type": "text", "text": text]
        applyCache(&block)
        content.append(block)
    }

    private func appendToolUseBlocks(from message: Message, to content: inout [[String: Any]]) {
        guard message.role == .assistant, let toolCalls = message.toolCalls else { return }
        for call in toolCalls {
            let input = call.arguments.mapValues { $0.value }
            content.append([
                "type": "tool_use",
                "id": call.id,
                "name": call.name,
                "input": input
            ])
        }
    }

    private func anthropicBlockCacheControl(
        from contextCache: ContextCacheControls?,
        strategy: ContextCacheStrategy
    ) -> [String: Any]? {
        guard strategy != .prefixWindow else { return nil }
        return anthropicEphemeralCacheControl(from: contextCache)
    }

    private func anthropicTopLevelCacheControl(
        from contextCache: ContextCacheControls?,
        strategy: ContextCacheStrategy
    ) -> [String: Any]? {
        guard strategy == .prefixWindow else { return nil }
        return anthropicEphemeralCacheControl(from: contextCache)
    }

    private func anthropicEphemeralCacheControl(from contextCache: ContextCacheControls?) -> [String: Any]? {
        let mode = contextCache?.mode ?? .implicit
        guard mode != .off else { return nil }

        var out: [String: Any] = ["type": "ephemeral"]
        if let ttl = contextCache?.ttl?.providerTTLString {
            out["ttl"] = ttl
        }
        return out
    }

}

// Stream parsing and search activities: AnthropicStreamParsing.swift
// Response types: AnthropicAdapterResponseTypes.swift
