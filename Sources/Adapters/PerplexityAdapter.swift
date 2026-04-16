import Foundation

/// Perplexity Sonar (OpenAI-compatible Chat Completions)
actor PerplexityAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    /// Perplexity supports streaming, vision, and web-grounded search. Function calling is OpenAI-compatible.
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

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoningOrReasoningContent,
            networkManager: networkManager
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        // Perplexity does not expose a lightweight auth check; use a minimal completion with small max_tokens.
        let body: [String: Any] = [
            "model": "sonar",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1,
            "stream": false
        ]

        let request = try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: key,
            body: body,
            includeUserAgent: false
        )

        do {
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            return false
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        if !providerConfig.models.isEmpty {
            return providerConfig.models
        }

        return [
            ModelInfo(
                id: "sonar",
                name: "Sonar",
                capabilities: [.streaming, .vision],
                contextWindow: 128_000,
                reasoningConfig: nil
            ),
            ModelInfo(
                id: "sonar-pro",
                name: "Sonar Pro",
                capabilities: [.streaming, .toolCalling, .vision],
                contextWindow: 200_000,
                reasoningConfig: nil
            ),
            ModelInfo(
                id: "sonar-reasoning-pro",
                name: "Sonar Reasoning Pro",
                capabilities: [.streaming, .toolCalling, .vision, .reasoning],
                contextWindow: 128_000,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            ),
            ModelInfo(
                id: "sonar-deep-research",
                name: "Sonar Deep Research",
                capabilities: [.streaming, .toolCalling, .reasoning],
                contextWindow: 128_000,
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            )
        ]
    }

    // MARK: - Private

    private var baseURL: String {
        let raw = (providerConfig.baseURL ?? ProviderType.perplexity.defaultBaseURL ?? "https://api.perplexity.ai")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    private func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var body: [String: Any] = [
            "model": modelID,
            "messages": try translateMessages(messages),
            "stream": streaming
        ]

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        if let reasoningEffort = mapReasoningEffort(controls.reasoning) {
            body["reasoning_effort"] = reasoningEffort
        }

        if supportsWebSearch(modelID: modelID), let webSearch = controls.webSearch {
            if webSearch.enabled == false {
                body["disable_search"] = true
            } else if let contextSize = webSearch.contextSize {
                body["web_search_options"] = [
                    "search_context_size": contextSize.rawValue
                ]
            }
        }

        if containsImage(messages) {
            body["has_image_url"] = true
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        if !controls.providerSpecific.isEmpty {
            deepMergeDictionary(into: &body, additional: controls.providerSpecific.mapValues { $0.value })
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            body: body,
            includeUserAgent: false
        )
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(message.content, separator: "\n", includeImages: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .assistant:
            dict["content"] = split.visible
            if let thinking = split.thinkingOrNil {
                dict["reasoning"] = thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(message.content, audioPartBuilder: nil)
            } else {
                dict["content"] = split.visible
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    private func containsImage(_ messages: [Message]) -> Bool {
        messages.contains { message in
            message.content.contains { part in
                if case .image = part { return true }
                return false
            }
        }
    }

    private func supportsWebSearch(modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    private func mapReasoningEffort(_ reasoning: ReasoningControls?) -> String? {
        guard let reasoning else { return nil }
        guard reasoning.enabled else { return nil }

        switch reasoning.effort ?? .medium {
        case .minimal:
            return "minimal"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh, .max:
            return "high"
        case .none:
            return nil
        }
    }

}
