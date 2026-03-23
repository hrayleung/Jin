import Foundation

/// OpenCode Go provider adapter.
///
/// Routes requests to the correct endpoint format based on model ID:
/// - GLM-5, Kimi K2.5 → OpenAI-compatible `/chat/completions`
/// - MiniMax M2.7, M2.5 → Anthropic-compatible `/messages`
///
/// Docs: https://opencode.ai/docs/go/
actor OpenCodeGoAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning]

    private let apiKey: String
    private let networkManager: NetworkManager
    private let anthropicDelegate: AnthropicAdapter

    private static let hardcodedBaseURL = "https://opencode.ai/zen/go/v1"
    private static let anthropicModelIDs: Set<String> = ["minimax-m2.7", "minimax-m2.5"]

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager

        let delegateConfig = ProviderConfig(
            id: providerConfig.id,
            name: providerConfig.name,
            type: .opencodeGo,
            baseURL: Self.hardcodedBaseURL,
            models: providerConfig.models
        )
        self.anthropicDelegate = AnthropicAdapter(
            providerConfig: delegateConfig,
            apiKey: apiKey,
            networkManager: networkManager
        )
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        if Self.isAnthropicModel(modelID) {
            return try await anthropicDelegate.sendMessage(
                messages: messages,
                modelID: modelID,
                controls: controls,
                tools: tools,
                streaming: streaming
            )
        }

        let request = try buildOpenAIRequest(
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
        let modelID = providerConfig.models.first?.id
            ?? ModelCatalog.seededModels(for: .opencodeGo).first?.id
            ?? "glm-5"

        let body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1,
            "stream": false
        ]

        do {
            let request = try makeAuthorizedJSONRequest(
                url: validatedURL("\(Self.hardcodedBaseURL)/chat/completions"),
                apiKey: key,
                body: body
            )
            _ = try await networkManager.sendRequest(request)
            return true
        } catch {
            let errorMessage = "\(error)".lowercased()
            if errorMessage.contains("401") || errorMessage.contains("403")
                || errorMessage.contains("authentication") || errorMessage.contains("unauthorized")
                || (errorMessage.contains("invalid") && errorMessage.contains("key")) {
                return false
            }
            return true
        }
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        (ModelCatalog.orderedRecords[.opencodeGo] ?? []).map { r in
            ModelInfo(
                id: r.id, name: r.displayName, capabilities: r.capabilities,
                contextWindow: r.contextWindow, maxOutputTokens: r.maxOutputTokens,
                reasoningConfig: r.reasoningConfig
            )
        }
    }

    // MARK: - Private

    private static func isAnthropicModel(_ modelID: String) -> Bool {
        anthropicModelIDs.contains(modelID.lowercased())
    }

    private func buildOpenAIRequest(
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
        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }

        if let reasoning = controls.reasoning {
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == .none {
                body["reasoning"] = ["effort": "none"]
            } else if let effort = reasoning.effort {
                body["reasoning"] = ["effort": mapReasoningEffort(effort)]
            }
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(Self.hardcodedBaseURL)/chat/completions"),
            apiKey: apiKey,
            body: body
        )
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(message.content, includeImages: true, includeAudio: true)

        var dict: [String: Any] = ["role": message.role.rawValue]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(message.content)
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
                dict["reasoning_content"] = split.thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
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
}
