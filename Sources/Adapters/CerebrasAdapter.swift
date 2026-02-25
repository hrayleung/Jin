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
        var request = URLRequest(url: try validatedURL("\(baseURLRoot)/v1/models"))
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
        var request = URLRequest(url: try validatedURL("\(baseURLRoot)/v1/models"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Jin", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateToolToOpenAIFormat)
    }

    // MARK: - Private

    private var baseURLRoot: String {
        let raw = (providerConfig.baseURL ?? "https://api.cerebras.ai")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripTrailingV1(raw)
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: try validatedURL("\(baseURLRoot)/v1/chat/completions"))
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
        translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) -> [String: Any] {
        let split = splitContentParts(
            message.content,
            imageUnsupportedMessage: "[Image attachment omitted: this provider does not support vision in Jin yet]"
        )

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system, .user:
            dict["content"] = split.visible

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            let combinedContent: String
            if !split.thinking.isEmpty {
                // Cerebras reasoning docs recommend embedding prior thinking in the assistant content using <think> tags.
                if split.visible.isEmpty {
                    combinedContent = "<think>\(split.thinking)</think>"
                } else {
                    combinedContent = "<think>\(split.thinking)</think>\n\(split.visible)"
                }
            } else {
                combinedContent = split.visible
            }

            dict["content"] = combinedContent.isEmpty ? (hasToolCalls ? NSNull() : "") : combinedContent

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        let lower = id.lowercased()

        var caps: ModelCapability = [.streaming, .toolCalling]
        var contextWindow = 128000
        var reasoningConfig: ModelReasoningConfig?

        if lower == "zai-glm-4.7" {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .toggle)
            contextWindow = 131_072
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
