import Foundation

/// Fireworks provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.fireworks.ai/inference/v1
/// - Endpoint: POST /chat/completions
/// - Models: `fireworks/kimi-k2p5`, `fireworks/glm-4p7`, ...
actor FireworksAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

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

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ChatCompletionResponse.self, from: data)

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: response.id))

                for choice in response.choices {
                    if let reasoning = choice.message.reasoningContent, !reasoning.isEmpty {
                        continuation.yield(.thinkingDelta(.thinking(textDelta: reasoning, signature: nil)))
                    }
                    if let content = choice.message.content, !content.isEmpty {
                        continuation.yield(.contentDelta(.text(content)))
                    }

                    if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty {
                        for call in toolCalls {
                            let name = call.function.name ?? ""
                            let arguments = parseJSONObject(call.function.arguments ?? "")
                            let toolCall = ToolCall(id: call.id ?? UUID().uuidString, name: name, arguments: arguments)
                            continuation.yield(.toolCallStart(toolCall))
                            continuation.yield(.toolCallEnd(toolCall))
                        }
                    }
                }

                continuation.yield(.messageEnd(usage: response.toUsage()))
                continuation.finish()
            }
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var didStart = false
                    var messageID: String = UUID().uuidString
                    var pendingUsage: Usage?
                    var toolCallsByIndex: [Int: ToolCallState] = [:]

                    for try await event in sseStream {
                        switch event {
                        case .event(_, let data):
                            guard let jsonData = data.data(using: .utf8) else { continue }
                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase

                            let chunk = try decoder.decode(ChatCompletionChunk.self, from: jsonData)

                            if !didStart {
                                messageID = chunk.id ?? messageID
                                continuation.yield(.messageStart(id: messageID))
                                didStart = true
                            }

                            if let usage = chunk.toUsage() {
                                pendingUsage = usage
                            }

                            // We only support the first choice in streaming mode today.
                            guard let choice = chunk.choices.first else { continue }

                            if let delta = choice.delta.reasoningContent, !delta.isEmpty {
                                continuation.yield(.thinkingDelta(.thinking(textDelta: delta, signature: nil)))
                            }

                            if let delta = choice.delta.content, !delta.isEmpty {
                                continuation.yield(.contentDelta(.text(delta)))
                            }

                            if let toolDeltas = choice.delta.toolCalls {
                                for toolDelta in toolDeltas {
                                    guard let index = toolDelta.index else { continue }

                                    if toolCallsByIndex[index] == nil {
                                        toolCallsByIndex[index] = ToolCallState(
                                            callID: toolDelta.id ?? "",
                                            name: toolDelta.function?.name ?? ""
                                        )
                                    }

                                    if let id = toolDelta.id, !id.isEmpty {
                                        toolCallsByIndex[index]?.callID = id
                                    }
                                    if let name = toolDelta.function?.name, !name.isEmpty {
                                        toolCallsByIndex[index]?.name = name
                                    }

                                    if toolCallsByIndex[index]?.didEmitStart == false,
                                       let state = toolCallsByIndex[index],
                                       !state.callID.isEmpty,
                                       !state.name.isEmpty {
                                        toolCallsByIndex[index]?.didEmitStart = true
                                        continuation.yield(.toolCallStart(ToolCall(id: state.callID, name: state.name, arguments: [:])))
                                    }

                                    if let argsDelta = toolDelta.function?.arguments, !argsDelta.isEmpty {
                                        toolCallsByIndex[index]?.argumentsBuffer.append(argsDelta)
                                        if let id = toolCallsByIndex[index]?.callID, !id.isEmpty {
                                            continuation.yield(.toolCallDelta(id: id, argumentsDelta: argsDelta))
                                        }
                                    }
                                }
                            }

                        case .done:
                            // Finalize any pending tool calls.
                            for (_, state) in toolCallsByIndex.sorted(by: { $0.key < $1.key }) {
                                guard !state.callID.isEmpty, !state.name.isEmpty else { continue }
                                let args = parseJSONObject(state.argumentsBuffer)
                                continuation.yield(.toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args)))
                            }

                            continuation.yield(.messageEnd(usage: pendingUsage))
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
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

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
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURL: String {
        providerConfig.baseURL ?? "https://api.fireworks.ai/inference/v1"
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages),
            "stream": streaming
        ]

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }

        // Fireworks reasoning controls: `reasoning_effort` (string/bool/int) + `reasoning_history` (for Kimi/GLM 4.7).
        if let reasoning = controls.reasoning {
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == .none {
                body["reasoning_effort"] = "none"
            } else if let effort = reasoning.effort {
                body["reasoning_effort"] = mapReasoningEffort(effort)
            }
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func translateMessages(_ messages: [Message]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        out.reserveCapacity(messages.count + 4)

        for message in messages {
            switch message.role {
            case .tool:
                if let toolResults = message.toolResults {
                    for result in toolResults {
                        out.append([
                            "role": "tool",
                            "tool_call_id": result.toolCallID,
                            "content": result.content
                        ])
                    }
                }

            case .system, .user, .assistant:
                out.append(translateNonToolMessage(message))

                if let toolResults = message.toolResults {
                    for result in toolResults {
                        out.append([
                            "role": "tool",
                            "tool_call_id": result.toolCallID,
                            "content": result.content
                        ])
                    }
                }
            }
        }

        return out
    }

    private func translateNonToolMessage(_ message: Message) -> [String: Any] {
        let (visibleContent, thinkingContent, hasImage) = splitContent(message.content)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = visibleContent

        case .user:
            if hasImage {
                dict["content"] = translateUserContentParts(message.content)
            } else {
                dict["content"] = visibleContent
            }

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            if visibleContent.isEmpty {
                // OpenAI-style: assistant content can be null when tool_calls exist.
                dict["content"] = hasToolCalls ? NSNull() : ""
            } else {
                dict["content"] = visibleContent
            }

            if !thinkingContent.isEmpty {
                // Fireworks returns this as `reasoning_content`; preserving it improves multi-turn stability for supported models.
                dict["reasoning_content"] = thinkingContent
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCalls(toolCalls)
            }

        case .tool:
            // Not used here; tool results are expanded in translateMessages(_:).
            dict["content"] = ""
        }

        return dict
    }

    private func translateUserContentParts(_ parts: [ContentPart]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        out.reserveCapacity(parts.count)

        for part in parts {
            switch part {
            case .text(let text):
                out.append([
                    "type": "text",
                    "text": text
                ])

            case .image(let image):
                if let urlString = imageURLString(image) {
                    out.append([
                        "type": "image_url",
                        "image_url": [
                            "url": urlString
                        ]
                    ])
                }

            case .file(let file):
                let text = AttachmentPromptRenderer.fallbackText(for: file)
                out.append([
                    "type": "text",
                    "text": text
                ])

            case .thinking, .redactedThinking, .audio:
                // Do not send provider reasoning blocks or audio via Chat Completions.
                continue
            }
        }

        return out
    }

    private func imageURLString(_ image: ImageContent) -> String? {
        if let data = image.data {
            return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
        }
        if let url = image.url {
            if url.isFileURL, let data = try? Data(contentsOf: url) {
                return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
            }
            return url.absoluteString
        }
        return nil
    }

    private func splitContent(_ parts: [ContentPart]) -> (visible: String, thinking: String, hasImage: Bool) {
        var visibleParts: [String] = []
        visibleParts.reserveCapacity(parts.count)

        var thinkingParts: [String] = []
        thinkingParts.reserveCapacity(2)

        var hasImage = false

        for part in parts {
            switch part {
            case .text(let text):
                visibleParts.append(text)
            case .file(let file):
                visibleParts.append(AttachmentPromptRenderer.fallbackText(for: file))
            case .image:
                hasImage = true
            case .thinking(let thinking):
                thinkingParts.append(thinking.text)
            case .redactedThinking:
                // Redacted reasoning is not safe to replay as model input.
                continue
            case .audio:
                continue
            }
        }

        return (visibleParts.joined(), thinkingParts.joined(), hasImage)
    }

    private func translateToolCalls(_ calls: [ToolCall]) -> [[String: Any]] {
        calls.map { call in
            [
                "id": call.id,
                "type": "function",
                "function": [
                    "name": call.name,
                    "arguments": encodeJSONObject(call.arguments)
                ]
            ]
        }
    }

    private func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        var propertiesDict: [String: Any] = [:]
        for (key, prop) in tool.parameters.properties {
            propertiesDict[key] = prop.toDictionary()
        }

        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": tool.parameters.type,
                    "properties": propertiesDict,
                    "required": tool.parameters.required
                ]
            ]
        ]
    }

    private func encodeJSONObject(_ object: [String: AnyCodable]) -> String {
        let raw = object.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func parseJSONObject(_ jsonString: String) -> [String: AnyCodable] {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.mapValues(AnyCodable.init)
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        // Fireworks supports: none, low, medium, high (and may accept ints/bools for some models).
        switch effort {
        case .none:
            return "none"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh:
            return "high"
        }
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        let lower = id.lowercased()
        let isKimiK2p5 = lower == "fireworks/kimi-k2p5" || lower == "accounts/fireworks/models/kimi-k2p5"
        let isGLM4p7 = lower == "fireworks/glm-4p7" || lower == "accounts/fireworks/models/glm-4p7"

        var caps: ModelCapability = [.streaming, .toolCalling]
        var reasoningConfig: ModelReasoningConfig?
        var contextWindow = 128000

        // Known models we explicitly support well.
        if isKimiK2p5 {
            caps.insert(.vision)
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            // Kimi K2.* models are commonly long-context (often 256k+). Keep conservative by default.
            contextWindow = 128000
        } else if isGLM4p7 {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        } else if lower.contains("kimi") || lower.contains("glm") {
            caps.insert(.reasoning)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }
}

// MARK: - DTOs

private struct ModelsResponse: Codable {
    let data: [Model]

    struct Model: Codable {
        let id: String
    }
}

private struct ChatCompletionResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: UsageInfo?

    struct Choice: Codable {
        let message: AssistantMessage
        let finishReason: String?
    }

    struct AssistantMessage: Codable {
        let role: String?
        let content: String?
        let reasoningContent: String?
        let toolCalls: [ToolCall]?
    }

    struct ToolCall: Codable {
        let id: String?
        let type: String?
        let function: Function

        struct Function: Codable {
            let name: String?
            let arguments: String?
        }
    }

    struct UsageInfo: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
    }

    func toUsage() -> Usage? {
        guard let usage else { return nil }
        guard let input = usage.promptTokens, let output = usage.completionTokens else { return nil }
        return Usage(inputTokens: input, outputTokens: output)
    }
}

private struct ChatCompletionChunk: Codable {
    let id: String?
    let choices: [Choice]
    let usage: ChatCompletionResponse.UsageInfo?

    struct Choice: Codable {
        let index: Int?
        let delta: Delta
        let finishReason: String?
    }

    struct Delta: Codable {
        let role: String?
        let content: String?
        let reasoningContent: String?
        let toolCalls: [ToolCallDelta]?
    }

    struct ToolCallDelta: Codable {
        let index: Int?
        let id: String?
        let type: String?
        let function: FunctionDelta?

        struct FunctionDelta: Codable {
            let name: String?
            let arguments: String?
        }
    }

    func toUsage() -> Usage? {
        guard let usage else { return nil }
        guard let input = usage.promptTokens, let output = usage.completionTokens else { return nil }
        return Usage(inputTokens: input, outputTokens: output)
    }
}

private struct ToolCallState {
    var callID: String
    var name: String
    var argumentsBuffer: String = ""
    var didEmitStart: Bool = false
}
