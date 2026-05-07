import Foundation

extension PerplexityAdapter {
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

        applyWebSearchControls(to: &body, modelID: modelID, controls: controls.webSearch)

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

    private func applyWebSearchControls(
        to body: inout [String: Any],
        modelID: String,
        controls: WebSearchControls?
    ) {
        guard modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID),
              let controls else { return }

        if controls.enabled == false {
            body["disable_search"] = true
        } else if let contextSize = controls.contextSize {
            body["web_search_options"] = [
                "search_context_size": contextSize.rawValue
            ]
        }
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
