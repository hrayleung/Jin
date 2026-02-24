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
                    var currentToolUse: ToolCallBuilder?
                    var currentServerToolUse: SearchActivityBuilder?
                    var currentContentBlockType: String?
                    var currentThinkingSignature: String?
                    var usageAccumulator = AnthropicUsageAccumulator()

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            if let streamEvent = try parseJSONLine(
                                data,
                                currentMessageID: &currentMessageID,
                                currentBlockIndex: &currentBlockIndex,
                                currentToolUse: &currentToolUse,
                                currentServerToolUse: &currentServerToolUse,
                                currentContentBlockType: &currentContentBlockType,
                                currentThinkingSignature: &currentThinkingSignature,
                                usageAccumulator: &usageAccumulator
                            ) {
                                continuation.yield(streamEvent)
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
        var request = URLRequest(url: try validatedURL("\(baseURL)/models"))
        request.httpMethod = "GET"
        request.addValue(key, forHTTPHeaderField: "x-api-key")
        request.addValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

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

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

            let (data, _) = try await networkManager.sendRequest(request)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ModelsListResponse.self, from: data)

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
        if let model = configuredModel(for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
            return resolved.supportsWebSearch
        }

        return ModelCapabilityRegistry.supportsWebSearch(
            for: providerConfig.type,
            modelID: modelID
        )
    }

    private func supportsWebSearchDynamicFiltering(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
            for: providerConfig.type,
            modelID: modelID
        )
    }

    private func configuredModel(for modelID: String) -> ModelInfo? {
        if let exact = providerConfig.models.first(where: { $0.id == modelID }) {
            return exact
        }
        let target = modelID.lowercased()
        return providerConfig.models.first(where: { $0.id.lowercased() == target })
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

        var request = URLRequest(url: try validatedURL("\(baseURL)/messages"))
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if let betaHeader = extractAnthropicBetaHeader(from: controls) {
            request.addValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        }

        let translatedMessages = normalizedMessages
            .filter { $0.role != .system }
            .map { message -> [String: Any] in
                return translateMessage(
                    message,
                    supportsNativePDF: supportsNativePDF,
                    cacheControl: blockCacheControl,
                    cacheStrategy: cacheStrategy
                )
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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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
            if supportsAdaptiveThinking(modelID), controls.reasoning?.budgetTokens == nil {
                body["thinking"] = ["type": "adaptive"]
            } else {
                body["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": controls.reasoning?.budgetTokens ?? 2048
                ]
            }
        }

        if supportsEffort(modelID),
           controls.reasoning?.budgetTokens == nil,
           let effort = controls.reasoning?.effort {
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
    ) -> [String: Any] {
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
        appendUserFacingBlocks(from: message, supportsNativePDF: supportsNativePDF, to: &content, applyCache: maybeApplyCache)
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
                var block: [String: Any] = [
                    "type": "thinking",
                    "thinking": thinking.text
                ]
                if let signature = thinking.signature {
                    block["signature"] = signature
                }
                content.append(block)
            case .redactedThinking(let redacted):
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
    ) {
        guard message.role != .tool else { return }
        for part in message.content {
            switch part {
            case .text(let text):
                var block: [String: Any] = ["type": "text", "text": text]
                applyCache(&block)
                content.append(block)
            case .image(let image):
                if let imageBlock = translateImageBlock(image) {
                    content.append(imageBlock)
                }
            case .file(let file):
                translateFileBlock(file, supportsNativePDF: supportsNativePDF, to: &content, applyCache: applyCache)
            case .video(let video):
                var block: [String: Any] = [
                    "type": "text",
                    "text": unsupportedVideoInputNotice(video, providerName: "Anthropic")
                ]
                applyCache(&block)
                content.append(block)
            default:
                break
            }
        }
    }

    private func translateImageBlock(_ image: ImageContent) -> [String: Any]? {
        let data: Data?
        if let existing = image.data {
            data = existing
        } else if let url = image.url, url.isFileURL {
            data = try? Data(contentsOf: url)
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
    ) {
        if supportsNativePDF && file.mimeType == "application/pdf" {
            let pdfData: Data?
            if let data = file.data {
                pdfData = data
            } else if let url = file.url, url.isFileURL {
                pdfData = try? Data(contentsOf: url)
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

    private func unsupportedVideoInputNotice(_ video: VideoContent, providerName: String) -> String {
        let detail: String
        if let url = video.url {
            detail = url.isFileURL ? url.lastPathComponent : url.absoluteString
        } else if let data = video.data {
            detail = "\(data.count) bytes"
        } else {
            detail = "no media payload"
        }
        return "Video attachment omitted (\(video.mimeType), \(detail)): \(providerName) Messages API does not support native video input in Jin yet."
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

    private func parseJSONLine(
        _ line: String,
        currentMessageID: inout String?,
        currentBlockIndex: inout Int?,
        currentToolUse: inout ToolCallBuilder?,
        currentServerToolUse: inout SearchActivityBuilder?,
        currentContentBlockType: inout String?,
        currentThinkingSignature: inout String?,
        usageAccumulator: inout AnthropicUsageAccumulator
    ) throws -> StreamEvent? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let event = try decoder.decode(StreamEvent_Anthropic.self, from: data)

        switch event.type {
        case "message_start":
            if let message = event.message {
                currentMessageID = message.id
                usageAccumulator.merge(message.usage)
                return .messageStart(id: message.id)
            }

        case "content_block_start":
            if let index = event.index, let contentBlock = event.contentBlock {
                currentBlockIndex = index
                currentContentBlockType = contentBlock.type

                if contentBlock.type == "thinking" {
                    currentThinkingSignature = contentBlock.signature
                    return .thinkingDelta(.thinking(textDelta: "", signature: currentThinkingSignature))
                }
                if contentBlock.type == "redacted_thinking", let data = contentBlock.data {
                    return .thinkingDelta(.redacted(data: data))
                }

                if contentBlock.type == "server_tool_use" {
                    let id = contentBlock.id ?? UUID().uuidString
                    let name = contentBlock.name ?? "server_tool_use"
                    let arguments = contentBlock.input ?? [:]
                    let builder = SearchActivityBuilder(id: id, type: name, arguments: arguments)
                    currentServerToolUse = builder
                    return .searchActivity(
                        SearchActivity(
                            id: id,
                            type: name,
                            status: .inProgress,
                            arguments: arguments,
                            outputIndex: index,
                            sequenceNumber: index
                        )
                    )
                }

                if contentBlock.type == "web_search_tool_result",
                   let activity = searchActivityFromWebSearchResult(contentBlock: contentBlock, outputIndex: index) {
                    return .searchActivity(activity)
                }

                if contentBlock.type == "text",
                   let activity = searchActivityFromTextCitations(contentBlock: contentBlock, outputIndex: index) {
                    return .searchActivity(activity)
                }

                // Only client-side tool_use should be executed by the app.
                if contentBlock.type == "tool_use" {
                    let toolUse = ToolCallBuilder(
                        id: contentBlock.id ?? UUID().uuidString,
                        name: contentBlock.name ?? ""
                    )
                    currentToolUse = toolUse
                    return .toolCallStart(ToolCall(
                        id: toolUse.id,
                        name: toolUse.name,
                        arguments: [:]
                    ))
                }
            }

        case "content_block_delta":
            if let delta = event.delta {
                if delta.type == "text_delta", let text = delta.text {
                    return .contentDelta(.text(text))
                } else if delta.type == "thinking_delta", let thinking = delta.thinking {
                    return .thinkingDelta(.thinking(textDelta: thinking, signature: currentThinkingSignature))
                } else if delta.type == "signature_delta", let signature = delta.signature {
                    // Some Anthropic models may stream signature incrementally; treat as an append.
                    if currentThinkingSignature == nil {
                        currentThinkingSignature = signature
                    } else {
                        currentThinkingSignature? += signature
                    }
                    return .thinkingDelta(.thinking(textDelta: "", signature: currentThinkingSignature))
                } else if delta.type == "input_json_delta", let partialJSON = delta.partialJson {
                    if currentContentBlockType == "server_tool_use",
                       let currentServerToolUse {
                        currentServerToolUse.appendArguments(partialJSON)
                        if let updated = currentServerToolUse.build(status: .searching, outputIndex: currentBlockIndex) {
                            return .searchActivity(updated)
                        }
                        return nil
                    } else if let currentToolUse {
                        currentToolUse.appendArguments(partialJSON)
                        return .toolCallDelta(id: currentToolUse.id, argumentsDelta: partialJSON)
                    }
                }
            }

        case "content_block_stop":
            if currentContentBlockType == "thinking" {
                currentThinkingSignature = nil
            }

            if currentContentBlockType == "server_tool_use",
               let serverToolUse = currentServerToolUse,
               let completed = serverToolUse.build(status: .completed, outputIndex: currentBlockIndex) {
                currentContentBlockType = nil
                currentBlockIndex = nil
                self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)
                return .searchActivity(completed)
            }
            currentContentBlockType = nil

            if let toolUse = currentToolUse, let toolCall = toolUse.build() {
                self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)
                return .toolCallEnd(toolCall)
            }

            self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)

        case "message_delta":
            if let usage = event.usage {
                usageAccumulator.merge(usage)
                return .messageEnd(usage: usageAccumulator.toUsage())
            }

        case "message_stop":
            return .messageEnd(usage: usageAccumulator.toUsage())

        default:
            break
        }

        return nil
    }

    private func currentToolCleanup(
        currentToolUse: inout ToolCallBuilder?,
        currentServerToolUse: inout SearchActivityBuilder?
    ) {
        currentToolUse = nil
        currentServerToolUse = nil
    }

    private func searchActivityFromWebSearchResult(
        contentBlock: StreamEvent_Anthropic.ContentBlock,
        outputIndex: Int
    ) -> SearchActivity? {
        guard let results = contentBlock.webSearchResults, !results.isEmpty else {
            return nil
        }

        var sources: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for result in results {
            guard let rawURL = result.url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                continue
            }

            let dedupeKey = rawURL.lowercased()
            guard !seenURLs.contains(dedupeKey) else { continue }
            seenURLs.insert(dedupeKey)

            var payload: [String: Any] = [
                "type": result.type ?? "web_search_result",
                "url": rawURL
            ]
            if let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                payload["title"] = title
            }
            if let snippet = (result.snippet ?? result.description)?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !snippet.isEmpty {
                payload["snippet"] = snippet
            }
            sources.append(payload)
        }

        guard !sources.isEmpty else { return nil }

        let id = contentBlock.toolUseId ?? contentBlock.id ?? "anthropic_web_search_result_\(outputIndex)"
        let arguments = searchActivityArguments(sources: sources)

        return SearchActivity(
            id: id,
            type: "web_search",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: outputIndex
        )
    }

    private func searchActivityFromTextCitations(
        contentBlock: StreamEvent_Anthropic.ContentBlock,
        outputIndex: Int
    ) -> SearchActivity? {
        guard let citations = contentBlock.citations, !citations.isEmpty else {
            return nil
        }

        var sources: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for citation in citations {
            guard citation.type == "web_search_result_location" || citation.type == "search_result_location" else {
                continue
            }

            let rawLocation = citation.url ?? citation.source
            guard let rawURL = rawLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                continue
            }

            let dedupeKey = rawURL.lowercased()
            guard !seenURLs.contains(dedupeKey) else { continue }
            seenURLs.insert(dedupeKey)

            var payload: [String: Any] = [
                "type": citation.type,
                "url": rawURL
            ]
            if let title = citation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                payload["title"] = title
            }
            if let citedText = citation.citedText?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !citedText.isEmpty {
                payload["snippet"] = citedText
            }
            sources.append(payload)
        }

        guard !sources.isEmpty else { return nil }

        let id = "anthropic_citation_\(outputIndex)"
        let arguments = searchActivityArguments(sources: sources)

        return SearchActivity(
            id: id,
            type: "url_citation",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: outputIndex
        )
    }

    private func searchActivityArguments(sources: [[String: Any]]) -> [String: AnyCodable] {
        guard !sources.isEmpty else { return [:] }

        var arguments: [String: AnyCodable] = [
            "sources": AnyCodable(sources)
        ]

        if let first = sources.first,
           let firstURL = first["url"] as? String {
            arguments["url"] = AnyCodable(firstURL)
            if let firstTitle = first["title"] as? String, !firstTitle.isEmpty {
                arguments["title"] = AnyCodable(firstTitle)
            }
        }

        return arguments
    }

    private func makeModelInfo(from model: ModelsListResponse.ModelInfo) -> ModelInfo {
        let id = model.id
        let name = model.displayName ?? id

        var caps: ModelCapability = [.streaming, .toolCalling, .vision, .promptCaching]
        var reasoningConfig: ModelReasoningConfig?
        let lower = id.lowercased()

        if id.contains("claude-") {
            caps.insert(.reasoning)
            if supportsEffort(id) {
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: defaultAnthropicEffort(for: id))
            } else {
                reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: 2048)
            }
        }

        // Claude 4.x series supports native PDF.
        if lower.contains("-4-") || lower.contains("-4.") {
            caps.insert(.nativePDF)
        }

        return ModelInfo(
            id: id,
            name: name,
            capabilities: caps,
            contextWindow: 200000,
            reasoningConfig: reasoningConfig,
            isEnabled: true
        )
    }
}

// MARK: - Response Types

private struct StreamEvent_Anthropic: Decodable {
    let type: String
    let message: MessageInfo?
    let index: Int?
    let contentBlock: ContentBlock?
    let delta: Delta?
    let usage: UsageInfo?

    struct MessageInfo: Decodable {
        let id: String
        let type: String
        let role: String
        let model: String
        let usage: UsageInfo?
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
        let signature: String?
        let data: String?
        let input: [String: AnyCodable]?
        let toolUseId: String?
        let webSearchResults: [WebSearchResult]?
        let citations: [TextCitation]?

        private enum CodingKeys: String, CodingKey {
            case type
            case id
            case name
            case signature
            case data
            case input
            case toolUseId
            case content
            case citations
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            signature = try container.decodeIfPresent(String.self, forKey: .signature)
            data = try container.decodeIfPresent(String.self, forKey: .data)
            input = try container.decodeIfPresent([String: AnyCodable].self, forKey: .input)
            toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
            webSearchResults = try? container.decode([WebSearchResult].self, forKey: .content)
            citations = try? container.decode([TextCitation].self, forKey: .citations)
        }
    }

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let thinking: String?
        let signature: String?
        let partialJson: String?
    }

    struct UsageInfo: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let serviceTier: String?
        let inferenceGeo: String?
    }

    struct WebSearchResult: Decodable {
        let type: String?
        let title: String?
        let url: String?
        let snippet: String?
        let description: String?
    }

    struct TextCitation: Decodable {
        let type: String
        let url: String?
        let source: String?
        let title: String?
        let citedText: String?
    }
}

private struct AnthropicUsageAccumulator {
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheCreationInputTokens: Int?
    var cacheReadInputTokens: Int?
    var serviceTier: String?
    var inferenceGeo: String?

    mutating func merge(_ usage: StreamEvent_Anthropic.UsageInfo?) {
        guard let usage else { return }
        if let inputTokens = usage.inputTokens {
            self.inputTokens = inputTokens
        }
        if let outputTokens = usage.outputTokens {
            self.outputTokens = outputTokens
        }
        if let cacheCreationInputTokens = usage.cacheCreationInputTokens {
            self.cacheCreationInputTokens = cacheCreationInputTokens
        }
        if let cacheReadInputTokens = usage.cacheReadInputTokens {
            self.cacheReadInputTokens = cacheReadInputTokens
        }
        if let serviceTier = usage.serviceTier {
            self.serviceTier = serviceTier
        }
        if let inferenceGeo = usage.inferenceGeo {
            self.inferenceGeo = inferenceGeo
        }
    }

    func toUsage() -> Usage? {
        guard inputTokens != nil
                || outputTokens != nil
                || cacheReadInputTokens != nil
                || cacheCreationInputTokens != nil else {
            return nil
        }

        return Usage(
            inputTokens: inputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            cachedTokens: cacheReadInputTokens,
            cacheCreationTokens: cacheCreationInputTokens,
            cacheWriteTokens: cacheCreationInputTokens,
            serviceTier: serviceTier,
            inferenceGeo: inferenceGeo
        )
    }
}

private struct ModelsListResponse: Codable {
    let data: [ModelInfo]
    let hasMore: Bool?
    let firstID: String?
    let lastID: String?

    struct ModelInfo: Codable {
        let id: String
        let displayName: String?
    }
}

private class ToolCallBuilder {
    let id: String
    let name: String
    var argumentsBuffer = ""

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    func appendArguments(_ delta: String) {
        argumentsBuffer += delta
    }

    func build() -> ToolCall? {
        guard let data = argumentsBuffer.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let arguments = json.mapValues { AnyCodable($0) }
        return ToolCall(id: id, name: name, arguments: arguments)
    }
}

private final class SearchActivityBuilder {
    let id: String
    let type: String
    private(set) var arguments: [String: AnyCodable]

    init(id: String, type: String, arguments: [String: AnyCodable]) {
        self.id = id
        self.type = type
        self.arguments = arguments
    }

    func appendArguments(_ delta: String) {
        guard let data = delta.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        for (key, value) in json {
            arguments[key] = AnyCodable(value)
        }
    }

    func build(status: SearchActivityStatus, outputIndex: Int?) -> SearchActivity? {
        SearchActivity(
            id: id,
            type: type,
            status: status,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: outputIndex
        )
    }
}
