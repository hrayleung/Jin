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

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            if let streamEvent = try parseJSONLine(
                                data,
                                currentMessageID: &currentMessageID,
                                currentBlockIndex: &currentBlockIndex,
                                currentToolUse: &currentToolUse,
                                currentContentBlockType: &currentContentBlockType,
                                currentThinkingSignature: &currentThinkingSignature
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
                    id: "claude-opus-4-5-20251101",
                    name: "Claude Opus 4.5",
                    capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
                    contextWindow: 200000,
                    reasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 4096)
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
        // Claude 4.5 series supports native PDF
        return modelID.contains("-4-5-") || modelID.contains("-4.5-")
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

        let translatedMessages = normalizedMessages
            .filter { $0.role != .system }
            .map { translateMessage($0, supportsNativePDF: supportsNativePDF) }

        try AnthropicRequestPreflight.validate(messages: translatedMessages)

        var body: [String: Any] = [
            "model": modelID,
            "messages": translatedMessages,
            "max_tokens": controls.maxTokens ?? 4096,
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
            body["thinking"] = [
                "type": "enabled",
                "budget_tokens": controls.reasoning?.budgetTokens ?? 2048
            ]
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
        currentThinkingSignature: inout String?
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

        case "message_delta":
            if let usage = event.usage {
                return .messageEnd(usage: Usage(
                    inputTokens: 0,
                    outputTokens: usage.outputTokens,
                    cachedTokens: nil
                ))
            }

        case "message_stop":
            return .messageEnd(usage: nil)

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

        if id.contains("claude-") {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: 2048)
        }

        // Claude 4.5 series supports native PDF
        if id.contains("-4-5-") || id.contains("-4.5-") {
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
        let outputTokens: Int
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
