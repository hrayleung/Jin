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
                                currentContentBlockType: &currentContentBlockType,
                                currentThinkingSignature: &currentThinkingSignature,
                                usageAccumulator: &usageAccumulator
                            ) {
                                continuation.yield(streamEvent)
                            }
                        case .done:
                            continuation.yield(.messageEnd(usage: nil))
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
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
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
        let cacheControl = anthropicCacheControl(from: controls.contextCache)
        let cacheStrategy = controls.contextCache?.strategy ?? .systemOnly

        var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if let betaHeader = extractAnthropicBetaHeader(from: controls) {
            request.addValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        }

        var userMessageOrdinal = 0
        let translatedMessages = normalizedMessages
            .filter { $0.role != .system }
            .map { message -> [String: Any] in
                if message.role != .assistant {
                    userMessageOrdinal += 1
                }
                return translateMessage(
                    message,
                    supportsNativePDF: supportsNativePDF,
                    cacheControl: cacheControl,
                    cacheStrategy: cacheStrategy,
                    userMessageOrdinal: userMessageOrdinal
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

        if let systemPrompt = normalizedMessages.first(where: { $0.role == .system })?.content.first,
           case .text(let text) = systemPrompt {
            var block: [String: Any] = [
                "type": "text",
                "text": text
            ]
            if let cacheControl {
                block["cache_control"] = cacheControl
            }
            body["system"] = [block]
        }

        let thinkingEnabled = controls.reasoning?.enabled == true
        let supportsAdaptive = supportsAdaptiveThinking(modelID)
        let supportsEffortControl = supportsEffort(modelID)
        let providerSpecificHasThinking = controls.providerSpecific["thinking"] != nil

        // When thinking is enabled, Anthropic rejects temperature/top_p.
        if !thinkingEnabled {
            if let temperature = controls.temperature {
                body["temperature"] = temperature
            }
            if let topP = controls.topP {
                body["top_p"] = topP
            }
        }

        if thinkingEnabled {
            if !providerSpecificHasThinking {
                if supportsAdaptive, controls.reasoning?.budgetTokens == nil {
                    body["thinking"] = [
                        "type": "adaptive"
                    ]
                } else {
                    body["thinking"] = [
                        "type": "enabled",
                        "budget_tokens": controls.reasoning?.budgetTokens ?? 2048
                    ]
                }
            }

            if supportsEffortControl,
               controls.reasoning?.budgetTokens == nil,
               let effort = controls.reasoning?.effort {
                mergeOutputConfig(
                    into: &body,
                    additional: [
                        "effort": mapAnthropicEffort(effort, modelID: modelID)
                    ]
                )
            }
        }

        var toolSpecs: [[String: Any]] = []

        if controls.webSearch?.enabled == true, supportsWebSearch(modelID) {
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
                spec["user_location"] = locDict
            }
            toolSpecs.append(spec)
        }

        if !tools.isEmpty, let customTools = translateTools(tools) as? [[String: Any]] {
            toolSpecs.append(contentsOf: customTools)
        }

        if !toolSpecs.isEmpty {
            body["tools"] = toolSpecs
        }

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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func translateMessage(
        _ message: Message,
        supportsNativePDF: Bool,
        cacheControl: [String: Any]?,
        cacheStrategy: ContextCacheStrategy,
        userMessageOrdinal: Int
    ) -> [String: Any] {
        var content: [[String: Any]] = []
        var didApplyPrefixCache = false

        func applyCacheControlIfNeeded(to block: inout [String: Any], isCacheableBlock: Bool) {
            guard isCacheableBlock, let cacheControl, message.role != .assistant else { return }

            switch cacheStrategy {
            case .systemOnly:
                return
            case .systemAndTools:
                block["cache_control"] = cacheControl
            case .prefixWindow:
                guard userMessageOrdinal == 1, !didApplyPrefixCache else { return }
                block["cache_control"] = cacheControl
                didApplyPrefixCache = true
            }
        }

        // Tool result blocks must come first in the user message that follows an assistant tool_use turn.
        // Even if some legacy history stores tool results on a non-`.tool` role, putting them first
        // keeps Anthropic's ordering rules satisfied.
        if let toolResults = message.toolResults {
            for result in toolResults {
                let trimmed = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let safeContent = trimmed.isEmpty ? "<empty_content>" : result.content

                var block: [String: Any] = [
                    "type": "tool_result",
                    "tool_use_id": result.toolCallID,
                    "content": safeContent,
                    "is_error": result.isError
                ]
                applyCacheControlIfNeeded(to: &block, isCacheableBlock: true)
                content.append(block)
            }
        }

        // Reasoning blocks first for assistant turns.
        if message.role == .assistant {
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

        // User-facing blocks (text/images/files).
        // For assistant tool_use turns, these should appear before the `tool_use` blocks.
        // For tool_result messages, these will appear after tool_result blocks (see above).
        if message.role != .tool {
            for part in message.content {
                switch part {
                case .text(let text):
                    var block: [String: Any] = [
                        "type": "text",
                        "text": text
                    ]
                    applyCacheControlIfNeeded(to: &block, isCacheableBlock: true)
                    content.append(block)
                case .image(let image):
                    if let data = image.data {
                        content.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": image.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    } else if let url = image.url, url.isFileURL, let data = try? Data(contentsOf: url) {
                        content.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": image.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    }
                case .file(let file):
                    // Native PDF support for Claude 4.5+
                    if supportsNativePDF && file.mimeType == "application/pdf" {
                        // Load PDF data from file URL or use existing data
                        let pdfData: Data?
                        if let data = file.data {
                            pdfData = data
                        } else if let url = file.url, url.isFileURL {
                            pdfData = try? Data(contentsOf: url)
                        } else {
                            pdfData = nil
                        }

                        if let pdfData = pdfData {
                            var block: [String: Any] = [
                                "type": "document",
                                "source": [
                                    "type": "base64",
                                    "media_type": "application/pdf",
                                    "data": pdfData.base64EncodedString()
                                ]
                            ]
                            applyCacheControlIfNeeded(to: &block, isCacheableBlock: true)
                            content.append(block)
                            continue
                        }
                    }

                    // Fallback to text extraction
                    let text = AttachmentPromptRenderer.fallbackText(for: file)
                    var block: [String: Any] = [
                        "type": "text",
                        "text": text
                    ]
                    applyCacheControlIfNeeded(to: &block, isCacheableBlock: true)
                    content.append(block)
                case .video(let video):
                    var block: [String: Any] = [
                        "type": "text",
                        "text": unsupportedVideoInputNotice(video, providerName: "Anthropic")
                    ]
                    applyCacheControlIfNeeded(to: &block, isCacheableBlock: true)
                    content.append(block)
                default:
                    break
                }
            }
        }

        // Append tool_use blocks last for assistant turns (Claude expects tool_use at the end
        // of the assistant content array).
        if message.role == .assistant, let toolCalls = message.toolCalls {
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

        return [
            "role": message.role == .assistant ? "assistant" : "user",
            "content": content
        ]
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

    private func anthropicCacheControl(from contextCache: ContextCacheControls?) -> [String: Any]? {
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

                // Only client-side tool_use should be executed by the app.
                // server_tool_use is executed by Anthropic and should not be surfaced as a ToolCall.
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
                    if let currentToolUse {
                        currentToolUse.appendArguments(partialJSON)
                        return .toolCallDelta(id: currentToolUse.id, argumentsDelta: partialJSON)
                    }
                }
            }

        case "content_block_stop":
            if currentContentBlockType == "thinking" {
                currentThinkingSignature = nil
            }
            currentContentBlockType = nil

            if let toolUse = currentToolUse, let toolCall = toolUse.build() {
                currentToolUse = nil
                return .toolCallEnd(toolCall)
            }

            currentToolUse = nil

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

private struct StreamEvent_Anthropic: Codable {
    let type: String
    let message: MessageInfo?
    let index: Int?
    let contentBlock: ContentBlock?
    let delta: Delta?
    let usage: UsageInfo?

    struct MessageInfo: Codable {
        let id: String
        let type: String
        let role: String
        let model: String
        let usage: UsageInfo?
    }

    struct ContentBlock: Codable {
        let type: String
        let id: String?
        let name: String?
        let signature: String?
        let data: String?
    }

    struct Delta: Codable {
        let type: String?
        let text: String?
        let thinking: String?
        let signature: String?
        let partialJson: String?
    }

    struct UsageInfo: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let serviceTier: String?
        let inferenceGeo: String?
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
