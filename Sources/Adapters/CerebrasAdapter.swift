import Foundation

/// Cerebras provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.cerebras.ai
/// - Endpoint: POST /v1/chat/completions
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
            let response = try OpenAIChatCompletionsCore.decodeResponse(data)
            return OpenAIChatCompletionsCore.makeNonStreamingStream(
                response: response,
                reasoningField: .reasoning
            )
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        return OpenAIChatCompletionsCore.makeStreamingStream(
            sseStream: sseStream,
            reasoningField: .reasoning
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURLRoot)/v1/models")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Jin", forHTTPHeaderField: "User-Agent")

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var request = URLRequest(url: URL(string: "\(baseURLRoot)/v1/models")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Jin", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateSingleTool)
    }

    // MARK: - Private

    private var baseURLRoot: String {
        // Cerebras docs use https://api.cerebras.ai + /v1/... paths. Users may paste a baseURL with /v1.
        // Normalize so both "https://api.cerebras.ai" and "https://api.cerebras.ai/v1" work.
        let raw = (providerConfig.baseURL ?? "https://api.cerebras.ai")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw

        if trimmed.hasSuffix("/v1") {
            let withoutV1 = String(trimmed.dropLast(3))
            return withoutV1.hasSuffix("/") ? String(withoutV1.dropLast()) : withoutV1
        }

        return trimmed
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURLRoot)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Jin", forHTTPHeaderField: "User-Agent")

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
                visibleParts.append(AttachmentPromptRenderer.fallbackText(for: file))
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
            case .video:
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
