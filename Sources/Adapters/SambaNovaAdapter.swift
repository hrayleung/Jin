import Foundation

/// SambaNova Cloud provider adapter (OpenAI-compatible Chat Completions API)
///
/// Docs:
/// - Base URL: https://api.sambanova.ai/v1
/// - Endpoint: POST /v1/chat/completions
/// - Models: `MiniMax-M2.5`, `DeepSeek-V3.1`, `gpt-oss-120b`, ...
///
/// SambaNova-specific parameters:
/// - `chat_template_kwargs: {"enable_thinking": true/false}` — toggles reasoning for
///    DeepSeek-V3.1 and Qwen3 models.
/// - `reasoning_effort: "low"/"medium"/"high"` — controls reasoning depth for gpt-oss-120b.
/// - Reasoning content is returned in `<think>` tags within content deltas.
actor SambaNovaAdapter: LLMProviderAdapter {
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

        return try await sendOpenAICompatibleMessage(
            request: request,
            streaming: streaming,
            reasoningField: .reasoningOrReasoningContent,
            networkManager: networkManager
        )
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        await validateAPIKeyViaGET(
            url: try validatedURL("\(baseURLRoot)/v1/models"),
            apiKey: key,
            networkManager: networkManager
        )
    }

    func fetchAvailableModels() async throws -> [ModelInfo] {
        let request = makeGETRequest(url: try validatedURL("\(baseURLRoot)/v1/models"), apiKey: apiKey)
        let (data, _) = try await networkManager.sendRequest(request)
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return response.data.map { makeModelInfo(id: $0.id) }
    }

    // MARK: - Private

    private var baseURLRoot: String {
        let raw = (providerConfig.baseURL ?? "https://api.sambanova.ai")
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
        let lower = modelID.lowercased()

        var body: [String: Any] = [
            "model": modelID,
            "messages": try translateMessages(messages, modelID: modelID),
            "stream": streaming
        ]

        if streaming {
            body["stream_options"] = ["include_usage": true]
        }

        // Temperature and top_p — omit for always-on reasoning models (DeepSeek-R1 family).
        let isAlwaysOnReasoningModel = lower.contains("deepseek-r1")
        if !isAlwaysOnReasoningModel {
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

        // Reasoning controls — provider-specific handling.
        applyReasoningControls(to: &body, controls: controls, modelID: modelID, lowerModelID: lower)

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURLRoot)/v1/chat/completions"),
            apiKey: apiKey,
            body: body
        )
    }

    /// Applies reasoning controls specific to each SambaNova model family.
    ///
    /// - gpt-oss-120b: Uses OpenAI-style `reasoning_effort` ("low"/"medium"/"high").
    /// - DeepSeek-V3.1 / Qwen3: Uses `chat_template_kwargs: {"enable_thinking": bool}`.
    /// - DeepSeek-R1 family: Always-on thinking, no toggle needed.
    private func applyReasoningControls(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String,
        lowerModelID: String
    ) {
        guard let reasoning = controls.reasoning else { return }

        if lowerModelID == "gpt-oss-120b" {
            // gpt-oss-120b uses reasoning_effort.
            if reasoning.enabled == false {
                // No way to fully disable reasoning on gpt-oss-120b, use lowest effort.
                body["reasoning_effort"] = "low"
            } else if let effort = reasoning.effort {
                body["reasoning_effort"] = mapReasoningEffort(effort)
            }
            return
        }

        if usesThinkingTemplateKwargs(lowerModelID) {
            // DeepSeek-V3.1, Qwen3 use chat_template_kwargs to toggle thinking.
            let enableThinking = reasoning.enabled != false
            body["chat_template_kwargs"] = ["enable_thinking": enableThinking]
            return
        }

        // DeepSeek-R1 family: always-on thinking, no explicit control needed.
    }

    /// Returns true for models that use `chat_template_kwargs: {"enable_thinking": ...}`.
    private func usesThinkingTemplateKwargs(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("deepseek-v3.1")
            || lowerModelID.hasPrefix("qwen3")
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high, .xhigh, .max:
            return "high"
        }
    }

    // MARK: - Message Translation

    private func translateMessages(_ messages: [Message], modelID: String) throws -> [[String: Any]] {
        let supportsVision = modelSupportsVision(modelID)
        return try translateMessagesToOpenAIFormat(messages) { message in
            try self.translateNonToolMessage(message, supportsVision: supportsVision)
        }
    }

    private func translateNonToolMessage(_ message: Message, supportsVision: Bool) throws -> [String: Any] {
        let split = splitContentParts(
            message.content,
            separator: "\n",
            includeImages: supportsVision,
            imageUnsupportedMessage: supportsVision
                ? nil
                : "[Image attachment omitted: this model does not support vision]"
        )

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if supportsVision, split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(message.content)
            } else {
                dict["content"] = split.visible
            }

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)

            // Re-inject prior thinking using <think> tags so the model can follow its chain of thought.
            let combinedContent: String
            if !split.thinking.isEmpty {
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

    // MARK: - Model Info

    /// Checks whether a model supports vision based on known model IDs.
    private func modelSupportsVision(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower.contains("minimax-m2.5")
            || lower.contains("maverick")
    }

    private func makeModelInfo(id: String) -> ModelInfo {
        // Prefer exact catalog metadata whenever the model ID is known.
        if ModelCatalog.entry(for: id, provider: .sambanova) != nil {
            return ModelCatalog.modelInfo(for: id, provider: .sambanova)
        }

        // Fallback heuristics for unknown models returned by the API.
        let lower = id.lowercased()
        var caps: ModelCapability = [.streaming, .toolCalling]
        var contextWindow = 128_000
        var reasoningConfig: ModelReasoningConfig?

        if lower.contains("deepseek-r1") {
            // DeepSeek-R1 variants expose tool calling on SambaNova, but reliability can vary.
            caps = [.streaming, .toolCalling, .reasoning]
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        } else if lower.contains("deepseek-v3.1") {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        } else if lower.contains("qwen3") {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .toggle)
        } else if lower == "gpt-oss-120b" {
            caps.insert(.reasoning)
            reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        } else if lower.contains("minimax-m2.5") {
            caps.insert(.vision)
            contextWindow = 160_000
        } else if lower.contains("maverick") {
            caps.insert(.vision)
        }

        if lower.contains("8b-instruct") {
            contextWindow = 16_000
        } else if lower.contains("qwen3-32b") {
            contextWindow = 32_000
        } else if lower.contains("qwen3-235b") {
            contextWindow = 64_000
        } else if lower.contains("deepseek-v3.2") {
            contextWindow = 8_192
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
