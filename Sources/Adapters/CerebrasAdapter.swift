import Foundation

/// Cerebras provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.cerebras.ai/v1
/// - Endpoint: POST /chat/completions
/// - Model: `zai-glm-4.7`
actor CerebrasAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .reasoning]

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
        // Cerebras OpenAI-compatible API does not support streaming when using tool calling on reasoning models.
        // Fall back to non-streaming to keep tool calling working.
        let effectiveStreaming = streaming && tools.isEmpty

        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: effectiveStreaming
        )

        if !effectiveStreaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ChatCompletionResponse.self, from: data)

            return AsyncThrowingStream { continuation in
                continuation.yield(.messageStart(id: response.id))

                for choice in response.choices {
                    if let reasoning = choice.message.reasoning, !reasoning.isEmpty {
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

                            guard let choice = chunk.choices.first else { continue }

                            if let delta = choice.delta.reasoning, !delta.isEmpty {
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
        providerConfig.baseURL ?? "https://api.cerebras.ai/v1"
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
            // Cerebras caps temperature at 1.5 (per docs). Clamp to avoid hard failures.
            body["temperature"] = min(max(temperature, 0), 1.5)
        }
        if let maxTokens = controls.maxTokens {
            body["max_completion_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }

        if let reasoning = controls.reasoning {
            body["disable_reasoning"] = (reasoning.enabled == false)
            // Prefer parsed reasoning so we can display it as a dedicated Thinking block in the UI.
            body["reasoning_format"] = (reasoning.enabled == false) ? "none" : "parsed"
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
        let (visibleContent, thinkingContent) = splitContent(message.content)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system, .user:
            dict["content"] = visibleContent

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            let combinedContent: String
            if !thinkingContent.isEmpty {
                // Cerebras reasoning docs recommend embedding prior thinking in the assistant content using <think> tags.
                if visibleContent.isEmpty {
                    combinedContent = "<think>\(thinkingContent)</think>"
                } else {
                    combinedContent = "<think>\(thinkingContent)</think>\n\(visibleContent)"
                }
            } else {
                combinedContent = visibleContent
            }

            dict["content"] = combinedContent.isEmpty ? (hasToolCalls ? NSNull() : "") : combinedContent

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCalls(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
    }

    private func splitContent(_ parts: [ContentPart]) -> (visible: String, thinking: String) {
        var visibleParts: [String] = []
        visibleParts.reserveCapacity(parts.count)

        var thinkingParts: [String] = []
        thinkingParts.reserveCapacity(2)

        for part in parts {
            switch part {
            case .text(let text):
                visibleParts.append(text)
            case .file(let file):
                let extracted = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let extracted, !extracted.isEmpty {
                    visibleParts.append("Attachment: \(file.filename) (\(file.mimeType))\n\n\(extracted)")
                } else {
                    visibleParts.append("Attachment: \(file.filename) (\(file.mimeType))")
                }
            case .image(let image):
                // Cerebras chat completions are text-only today. Keep a small placeholder to avoid silently dropping context.
                if image.url != nil || image.data != nil {
                    visibleParts.append("[Image attachment omitted: this provider does not support vision in Jin yet]")
                }
            case .thinking(let thinking):
                thinkingParts.append(thinking.text)
            case .redactedThinking:
                continue
            case .audio:
                continue
            }
        }

        return (visibleParts.joined(), thinkingParts.joined())
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

    private func makeModelInfo(id: String) -> ModelInfo {
        let lower = id.lowercased()

        var caps: ModelCapability = [.streaming, .toolCalling]
        var contextWindow = 128000
        var reasoningConfig: ModelReasoningConfig?

        if lower == "zai-glm-4.7" {
            caps.insert(.reasoning)
            // GLM 4.7 supports reasoning on/off via `disable_reasoning` (and preserved thinking via `clear_thinking`).
            reasoningConfig = ModelReasoningConfig(type: .toggle)
            contextWindow = 128000
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
        let reasoning: String?
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
        let reasoning: String?
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
