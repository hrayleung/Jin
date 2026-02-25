import Foundation

/// DeepSeek official provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.deepseek.com
/// - Endpoint: POST /chat/completions
/// - Models: `deepseek-chat`, `deepseek-reasoner`, `deepseek-v3.2-exp`, ...
actor DeepSeekAdapter: LLMProviderAdapter {
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
        let request = try buildRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let response = try OpenAIChatCompletionsCore.decodeResponse(data)
            return OpenAIChatCompletionsCore.makeNonStreamingStream(
                response: response,
                reasoningField: .reasoningContent
            )
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        return OpenAIChatCompletionsCore.makeStreamingStream(
            sseStream: sseStream,
            reasoningField: .reasoningContent
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
        let raw = (providerConfig.baseURL ?? "https://api.deepseek.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripTrailingV1(raw)
    }

    private var isDefaultHost: Bool {
        guard let url = URL(string: baseURLRoot), let host = url.host?.lowercased() else { return false }
        return host == "api.deepseek.com"
    }

    private func chatCompletionsURL(for modelID: String) throws -> URL {
        let lower = modelID.lowercased()
        if isDefaultHost, lower.contains("v3.2-exp") {
            return try validatedURL("\(baseURLRoot)/beta/chat/completions")
        }

        return try validatedURL("\(baseURLRoot)/v1/chat/completions")
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: try chatCompletionsURL(for: modelID))
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

        let isReasoningModel = modelID.lowercased().contains("reasoner")
        if !isReasoningModel {
            if let temperature = controls.temperature {
                body["temperature"] = temperature
            }
            if let topP = controls.topP {
                body["top_p"] = topP
            }
        }

        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        if let reasoning = controls.reasoning {
            if reasoning.enabled == false {
                body["reasoning"] = false
            } else if isReasoningModel {
                body["reasoning"] = true
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
            dict["content"] = split.visible.isEmpty ? (hasToolCalls ? NSNull() : "") : split.visible

            if !split.thinking.isEmpty {
                dict["reasoning_content"] = split.thinking
            }

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
        var reasoningConfig: ModelReasoningConfig?

        if lower.contains("reasoner") {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: caps,
            contextWindow: 128000,
            reasoningConfig: reasoningConfig
        )
    }
}
