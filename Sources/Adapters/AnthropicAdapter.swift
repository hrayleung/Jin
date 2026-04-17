import Foundation

actor AnthropicAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .promptCaching]

    let networkManager: NetworkManager
    let apiKey: String

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
        let request = try await buildRequest(
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
        if !supportsModelsEndpoint {
            return await validateAPIKeyViaMinimalMessage(key)
        }

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
        if !supportsModelsEndpoint {
            return (ModelCatalog.orderedRecords[providerConfig.type] ?? []).map { r in
                ModelInfo(
                    id: r.id, name: r.displayName, capabilities: r.capabilities,
                    contextWindow: r.contextWindow, maxOutputTokens: r.maxOutputTokens,
                    reasoningConfig: r.reasoningConfig
                )
            }
        }

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

    var baseURL: String {
        providerConfig.baseURL ?? "https://api.anthropic.com/v1"
    }

    /// Anthropic-compatible providers (e.g. MiniMax Coding Plan) may not expose a `/models` endpoint.
    private var supportsModelsEndpoint: Bool {
        providerConfig.type == .anthropic
    }

    /// Validate by sending a tiny message request and checking for auth errors.
    private func validateAPIKeyViaMinimalMessage(_ key: String) async -> Bool {
        let modelID = providerConfig.models.first?.id
            ?? ModelCatalog.seededModels(for: providerConfig.type).first?.id
            ?? "MiniMax-M2.7"

        let body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false
        ]

        do {
            let request = try NetworkRequestFactory.makeJSONRequest(
                url: validatedURL("\(baseURL)/messages"),
                headers: anthropicHeaders(apiKey: key),
                body: body
            )
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            let errorMessage = "\(error)".lowercased()
            if errorMessage.contains("401") || errorMessage.contains("403")
                || errorMessage.contains("authentication") || errorMessage.contains("unauthorized")
                || (errorMessage.contains("invalid") && errorMessage.contains("key")) {
                return false
            }
            // Non-auth errors (e.g. 400 bad request) still confirm the key is reachable.
            return true
        }
    }

    var anthropicVersion: String {
        "2023-06-01"
    }

    func anthropicHeaders(apiKey: String, contentType: String? = nil, betaHeader: String? = nil) -> [String: String] {
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

    private func supportsSamplingParameters(_ modelID: String) -> Bool {
        AnthropicModelLimits.supportsSamplingParameters(for: modelID)
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

    private func supportsCodeExecution(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: modelID)
    }

    private func mapAnthropicEffort(_ effort: ReasoningEffort, modelID: String) -> String {
        let normalized = ModelCapabilityRegistry.normalizedReasoningEffort(
            effort,
            for: .anthropic,
            modelID: modelID
        )

        switch normalized {
        case .none:
            return "high"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        case .max:
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

    private func mergedAnthropicBetaHeader(_ existing: String?, additions: [String]) -> String? {
        var values: [String] = []
        var seen: Set<String> = []

        func append(_ raw: String?) {
            guard let raw else { return }
            let parts = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for part in parts where seen.insert(part).inserted {
                values.append(part)
            }
        }

        append(existing)
        for addition in additions {
            append(addition)
        }

        return values.isEmpty ? nil : values.joined(separator: ",")
    }

    private func requestUsesAnthropicFiles(_ messages: [Message], codeExecutionEnabled: Bool) -> Bool {
        let allowedMIMETypes = codeExecutionEnabled
            ? anthropicHostedDocumentMIMETypes.union(anthropicCodeExecutionUploadMIMETypes)
            : anthropicHostedDocumentMIMETypes
        for message in messages {
            for part in message.content {
                guard case .file(let file) = part else { continue }
                let mimeType = normalizedMIMEType(file.mimeType)
                if allowedMIMETypes.contains(mimeType) {
                    return true
                }
            }
        }
        return false
    }

    private func mergeOutputConfig(into body: inout [String: Any], additional: [String: Any]) {
        guard !additional.isEmpty else { return }
        var merged = (body["output_config"] as? [String: Any]) ?? [:]
        for (key, value) in additional {
            merged[key] = value
        }
        body["output_config"] = merged
    }

    private func appendSamplingControls(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        guard supportsSamplingParameters(modelID) else { return }
        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> URLRequest {
        let normalizedMessages = AnthropicToolUseNormalizer.normalize(messages)
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let supportsNativePDF = allowNativePDF && self.supportsNativePDF(modelID)
        let codeExecutionEnabled = controls.codeExecution?.enabled == true && supportsCodeExecution(modelID)
        let cacheStrategy = controls.contextCache?.strategy ?? .systemOnly
        let blockCacheControl = anthropicBlockCacheControl(
            from: controls.contextCache,
            strategy: cacheStrategy
        )
        let topLevelCacheControl = anthropicTopLevelCacheControl(
            from: controls.contextCache,
            strategy: cacheStrategy
        )

        let betaHeader = mergedAnthropicBetaHeader(
            extractAnthropicBetaHeader(from: controls),
            additions: requestUsesAnthropicFiles(normalizedMessages, codeExecutionEnabled: codeExecutionEnabled) ? [anthropicFilesAPIBetaHeader] : []
        )

        let nonSystemMessages = normalizedMessages.filter { $0.role != .system }
        var translatedMessages: [[String: Any]] = []
        translatedMessages.reserveCapacity(nonSystemMessages.count)
        for message in nonSystemMessages {
            let translated = try await translateMessage(
                message,
                supportsNativePDF: supportsNativePDF,
                usesCodeExecutionTool: codeExecutionEnabled,
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
        appendToolSpecs(
            to: &body,
            controls: controls,
            tools: tools,
            modelID: modelID,
            codeExecutionEnabled: codeExecutionEnabled
        )
        if codeExecutionEnabled,
           let containerID = controls.codeExecution?.anthropic?.normalizedContainerID {
            body["container"] = containerID
        }
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
        let providerSpecificThinking = AnthropicThinkingConfigSupport.providerSpecificThinkingDictionary(
            from: controls.providerSpecific["thinking"]?.value
        )

        if !thinkingEnabled {
            appendSamplingControls(to: &body, controls: controls, modelID: modelID)
            return
        }

        if providerSpecificThinking == nil {
            if supportsAdaptiveThinking(modelID) {
                body["thinking"] = AnthropicThinkingConfigSupport.normalizedThinkingConfiguration(
                    ["type": "adaptive"],
                    reasoning: controls.reasoning,
                    modelID: modelID
                )
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

    private func appendToolSpecs(
        to body: inout [String: Any],
        controls: GenerationControls,
        tools: [ToolDefinition],
        modelID: String,
        codeExecutionEnabled: Bool
    ) {
        var toolSpecs: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
            toolSpecs.append(buildWebSearchToolSpec(controls: controls, modelID: modelID))
        }

        if codeExecutionEnabled {
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

            if (key == "temperature" || key == "top_p" || key == "top_k")
                && !supportsSamplingParameters(modelID) {
                continue
            }

            if key == "tools" {
                body[key] = normalizeAnthropicProviderSpecificTools(value.value, modelID: modelID)
                continue
            }

            if key == "thinking" {
                guard controls.reasoning?.enabled == true,
                      let dict = AnthropicThinkingConfigSupport.providerSpecificThinkingDictionary(from: value.value) else {
                    continue
                }
                body[key] = AnthropicThinkingConfigSupport.normalizedThinkingConfiguration(
                    dict,
                    reasoning: controls.reasoning,
                    modelID: modelID
                )
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

    // MARK: - Cache Control

    func anthropicBlockCacheControl(
        from contextCache: ContextCacheControls?,
        strategy: ContextCacheStrategy
    ) -> [String: Any]? {
        guard strategy != .prefixWindow else { return nil }
        return anthropicEphemeralCacheControl(from: contextCache)
    }

    func anthropicTopLevelCacheControl(
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
// Message translation: AnthropicAdapterMessageTranslation.swift
