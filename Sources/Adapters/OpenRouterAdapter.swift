import Foundation

/// OpenRouter provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://openrouter.ai/api/v1
/// - Endpoint: POST /chat/completions
/// - Models: GET /models
actor OpenRouterAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .audio, .reasoning]

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

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoningOrReasoningContent,
            networkManager: networkManager
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: try validatedURL("\(baseURL)/key"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        var request = URLRequest(url: try validatedURL("\(baseURL)/models"))
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

        let (data, _) = try await networkManager.sendRequest(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterModelsResponse.self, from: data)
        return response.data.map(makeModelInfo(from:))
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        tools.map(translateToolToOpenAIFormat)
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? "https://openrouter.ai/api/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let lower = trimmed.lowercased()

        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            return trimmed
        }

        if lower.hasSuffix("/api") {
            return "\(trimmed)/v1"
        }

        if let url = URL(string: trimmed),
           url.host?.lowercased().contains("openrouter.ai") == true,
           (url.path.isEmpty || url.path == "/") {
            return "\(trimmed)/api/v1"
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
        var request = URLRequest(url: try validatedURL("\(baseURL)/chat/completions"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages),
            "stream": streaming
        ]

        let requestShape = ModelCapabilityRegistry.requestShape(for: providerConfig.type, modelID: modelID)
        let shouldOmitSamplingControls = applyReasoning(
            to: &body,
            controls: controls,
            modelID: modelID,
            requestShape: requestShape
        )

        if !shouldOmitSamplingControls {
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

        if controls.webSearch?.enabled == true, modelSupportsWebSearch(for: modelID) {
            var plugins = body["plugins"] as? [[String: Any]] ?? []
            plugins.append(["id": "web"])
            body["plugins"] = plugins
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
        let split = splitContentParts(message.content, includeImages: true, includeAudio: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if split.hasRichUserContent {
                dict["content"] = translateUserContentPartsToOpenAIFormat(message.content)
            } else {
                dict["content"] = split.visible
            }

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            if split.visible.isEmpty {
                dict["content"] = hasToolCalls ? NSNull() : ""
            } else {
                dict["content"] = split.visible
            }

            if !split.thinking.isEmpty {
                dict["reasoning"] = split.thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
    }

    // MARK: - Reasoning

    /// OpenRouter-specific reasoning application. Adds `include_reasoning` field
    /// on top of the standard OpenAI-compatible reasoning logic.
    private func applyReasoning(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String,
        requestShape: ModelRequestShape
    ) -> Bool {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else {
            return false
        }
        guard let reasoning = controls.reasoning else { return false }

        switch requestShape {
        case .openAIResponses, .openAICompatible:
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                body["include_reasoning"] = false
                body["reasoning"] = ["effort": "none"]
                return false
            }

            let effort = reasoning.effort ?? .medium
            body["include_reasoning"] = true
            body["reasoning"] = [
                "effort": OpenAICompatibleReasoningSupport.mapReasoningEffort(
                    effort,
                    providerConfig: providerConfig,
                    modelID: modelID
                )
            ]
            return requestShape == .openAIResponses

        case .anthropic, .gemini:
            return OpenAICompatibleReasoningSupport.applyReasoning(
                to: &body,
                controls: controls,
                providerConfig: providerConfig,
                modelID: modelID,
                requestShape: requestShape
            )
        }
    }

    // MARK: - Web Search

    private func modelSupportsWebSearch(for modelID: String) -> Bool {
        guard let model = findConfiguredModel(in: providerConfig, for: modelID) else {
            return ModelCapabilityRegistry.supportsWebSearch(
                for: providerConfig.type,
                modelID: modelID
            )
        }

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
        return resolved.supportsWebSearch
    }

    // MARK: - Model Info

    private func makeModelInfo(from model: OpenRouterModelsResponse.Model) -> ModelInfo {
        let id = model.id
        let lower = id.lowercased()
        let inputModalities = Set((model.architecture?.inputModalities ?? []).map { $0.lowercased() })

        var caps: ModelCapability = [.streaming, .toolCalling]
        let reasoningConfig = ModelCapabilityRegistry.defaultReasoningConfig(for: providerConfig.type, modelID: id)
        let contextWindow = 128000

        if reasoningConfig != nil {
            caps.insert(.reasoning)
        }

        if inputModalities.contains(where: { $0.contains("image") || $0.contains("video") })
            || lower.contains("vision")
            || lower.contains("image")
            || lower.contains("/gpt-4o")
            || lower.contains("/gpt-5")
            || lower.contains("/gemini")
            || lower.contains("/claude") {
            caps.insert(.vision)
        }

        if inputModalities.contains(where: { $0.contains("audio") }) {
            caps.insert(.audio)
        }
        if supportsAudioInputModelID(lower) {
            caps.insert(.audio)
        }

        if lower.contains("image") {
            caps.insert(.imageGeneration)
        }

        return ModelInfo(
            id: id,
            name: id,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    private func supportsAudioInputModelID(_ lowerModelID: String) -> Bool {
        isAudioInputModelID(lowerModelID)
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
        let architecture: Architecture?
    }

    struct Architecture: Decodable {
        let inputModalities: [String]?
    }
}
