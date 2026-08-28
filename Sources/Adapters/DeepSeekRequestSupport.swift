import Foundation

extension DeepSeekAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var body: [String: Any] = [
            "model": modelID,
            "messages": try translateMessages(messages, modelID: modelID),
            "stream": streaming
        ]

        if !isReasoningModel(modelID) {
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

        applyReasoningControls(to: &body, modelID: modelID, controls: controls)

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: chatCompletionsURL(for: modelID),
            apiKey: apiKey,
            body: body
        )
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

    private func applyReasoningControls(
        to body: inout [String: Any],
        modelID: String,
        controls: GenerationControls
    ) {
        guard let reasoning = controls.reasoning else { return }

        let lower = modelID.lowercased()
        if isV4ReasoningModel(lower) {
            if reasoning.enabled == false || reasoning.effort == ReasoningEffort.none {
                body["thinking"] = ["type": "disabled"]
                return
            }

            body["thinking"] = ["type": "enabled"]
            let effort = reasoning.effort ?? .high
            body["reasoning_effort"] = mapDeepSeekReasoningEffort(effort)
            return
        }

        if reasoning.enabled == false {
            body["thinking"] = ["type": "disabled"]
        }
    }

    private func isReasoningModel(_ modelID: String) -> Bool {
        modelID.lowercased().contains("reasoner")
    }

    private func isV4ReasoningModel(_ lowerModelID: String) -> Bool {
        lowerModelID == "deepseek-v4-flash"
            || lowerModelID == "deepseek-v4-flash-0731"
            || lowerModelID == "deepseek-v4-flash-vision-exp"
            || lowerModelID == "deepseek-v4-pro"
            || lowerModelID == "deepseek-v4-pro-0813"
    }

    private func isVisionModel(_ lowerModelID: String) -> Bool {
        lowerModelID == "deepseek-v4-flash-vision-exp"
    }

    /// Official Chat Completions `reasoning_effort` is `low`/`high`/`max`
    /// (api-docs.deepseek.com thinking mode). Compatibility mapping from the
    /// same page: `medium` and `xhigh` fold to `high`; `max` stays `max`.
    private func mapDeepSeekReasoningEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .low:
            return "low"
        case .max:
            return "max"
        case .none, .minimal, .medium, .high, .xhigh:
            return "high"
        }
    }

    private func translateMessages(_ messages: [Message], modelID: String) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages) { message in
            try translateNonToolMessage(message, modelID: modelID)
        }
    }

    private func translateNonToolMessage(_ message: Message, modelID: String) throws -> [String: Any] {
        let visionEnabled = isVisionModel(modelID.lowercased())
        let split = splitContentParts(
            message.content,
            includeImages: visionEnabled && message.role == .user,
            imageUnsupportedMessage: visionEnabled && message.role == .user
                ? nil
                : "[Image attachment omitted: this provider does not support vision in Jin yet]"
        )

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if visionEnabled, split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(
                    message.content,
                    audioPartBuilder: nil
                )
            } else {
                dict["content"] = split.visible
            }

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            if split.visible.isEmpty, hasToolCalls {
                dict["content"] = NSNull()
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
            dict["content"] = ""
        }

        return dict
    }
}
