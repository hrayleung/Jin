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
        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        do {
            let (data, _) = try await networkManager.sendRequest(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ModelsListResponse.self, from: data)
            return response.data.map(makeModelInfo(from:))
        } catch {
            // Fallback (offline / restricted org / temporary outage): include a sane baseline set.
            return [
                ModelInfo(
                    id: "claude-opus-4-6",
                    name: "Claude Opus 4.6",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high)
                ),
                ModelInfo(
                    id: "claude-opus-4-5-20251101",
                    name: "Claude Opus 4.5",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048)
                ),
                ModelInfo(
                    id: "claude-sonnet-4-5-20250929",
                    name: "Claude Sonnet 4.5",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 2048)
                ),
                ModelInfo(
                    id: "claude-haiku-4-5-20251001",
                    name: "Claude Haiku 4.5",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 1024)
                )
            ]
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
        var result: [String: Any] = [:]
        for key in properties.keys {
            if let prop = properties[key] {
                result[key] = prop.toDictionary()
            }
        }
        return result
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

        var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if let betaHeader = extractAnthropicBetaHeader(from: controls) {
            request.addValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        }

        let translatedMessages = normalizedMessages
            .filter { $0.role != .system }
            .map { translateMessage($0, supportsNativePDF: supportsNativePDF) }

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
            body["system"] = [
                [
                    "type": "text",
                    "text": text,
                    "cache_control": ["type": "ephemeral"]
                ]
            ]
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

        if controls.webSearch?.enabled == true {
            // Anthropic server-side web search tool
            toolSpecs.append([
                "type": "web_search_20250305",
                "name": "web_search"
            ])
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

    private func translateMessage(_ message: Message, supportsNativePDF: Bool) -> [String: Any] {
        var content: [[String: Any]] = []

        // Tool result blocks must come first in the user message that follows an assistant tool_use turn.
        // Even if some legacy history stores tool results on a non-`.tool` role, putting them first
        // keeps Anthropic's ordering rules satisfied.
        if let toolResults = message.toolResults {
            for result in toolResults {
                let trimmed = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let safeContent = trimmed.isEmpty ? "<empty_content>" : result.content

                content.append([
                    "type": "tool_result",
                    "tool_use_id": result.toolCallID,
                    "content": safeContent,
                    "is_error": result.isError
                ])
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
                    content.append([
                        "type": "text",
                        "text": text
                    ])
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
                            content.append([
                                "type": "document",
                                "source": [
                                    "type": "base64",
                                    "media_type": "application/pdf",
                                    "data": pdfData.base64EncodedString()
                                ]
                            ])
                            continue
                        }
                    }

                    // Fallback to text extraction
                    let text = AttachmentPromptRenderer.fallbackText(for: file)
                    content.append([
                        "type": "text",
                        "text": text
                    ])
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
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
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
            reasoningConfig: reasoningConfig
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
            serviceTier: serviceTier,
            inferenceGeo: inferenceGeo
        )
    }
}

private struct ModelsListResponse: Codable {
    let data: [ModelInfo]

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
