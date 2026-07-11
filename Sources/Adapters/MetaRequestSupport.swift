import Foundation

extension MetaAdapter {
    func buildRequest(
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

        // Muse Spark is tuned for the default sampling settings and Meta documents
        // "use temperature or top_p, not both" — prefer temperature when both are set.
        if let temperature = controls.temperature {
            body["temperature"] = temperature
        } else if let topP = controls.topP {
            body["top_p"] = topP
        }
        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }

        applyReasoning(to: &body, controls: controls, modelID: modelID)
        applyContextCacheControls(to: &body, controls: controls)

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            body: body,
            includeUserAgent: false
        )
    }

    /// Meta's reasoning is always-on and `reasoning_effort: "none"` returns HTTP 400,
    /// so a disabled/none state omits the field and lets the model pick its own effort.
    /// Accepted values are minimal|low|medium|high|xhigh (no `max`).
    private func applyReasoning(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else { return }
        guard let reasoning = controls.reasoning, reasoning.enabled else { return }

        let effort = ModelCapabilityRegistry.normalizedReasoningEffort(
            reasoning.effort ?? .medium,
            for: providerConfig.type,
            modelID: modelID
        )

        switch effort {
        case .none:
            return
        case .minimal:
            body["reasoning_effort"] = "minimal"
        case .low:
            body["reasoning_effort"] = "low"
        case .medium:
            body["reasoning_effort"] = "medium"
        case .high:
            body["reasoning_effort"] = "high"
        case .xhigh, .max:
            body["reasoning_effort"] = "xhigh"
        }
    }

    /// Caching is implicit server-side; `prompt_cache_key` is an optional routing hint
    /// documented for both the Chat Completions and Responses surfaces.
    private func applyContextCacheControls(to body: inout [String: Any], controls: GenerationControls) {
        guard controls.contextCache?.mode != .off,
              let cacheKey = normalizedTrimmedString(controls.contextCache?.cacheKey) else {
            return
        }

        body["prompt_cache_key"] = cacheKey
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(message.content, separator: "\n", includeImages: true, includeAudio: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .assistant:
            dict["content"] = split.visible

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(message.content)
            } else {
                dict["content"] = split.visible
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }
}
