import Foundation

extension CerebrasAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        // Cerebras `clear_thinking` defaults to true. Only replay prior thinking
        // in assistant content when the user explicitly preserves it.
        let includeThinkingInHistory = (controls.providerSpecific["clear_thinking"]?.value as? Bool) == false

        var body: [String: Any] = [
            "model": modelID,
            "messages": translateMessages(messages, includeThinkingInHistory: includeThinkingInHistory),
            "stream": streaming
        ]

        if let temperature = controls.temperature {
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
            body["reasoning_format"] = (reasoning.enabled == false) ? "none" : "parsed"
        }

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

    private func translateMessages(_ messages: [Message], includeThinkingInHistory: Bool) -> [[String: Any]] {
        translateMessagesToOpenAIFormat(messages) { message in
            translateNonToolMessage(message, includeThinkingInHistory: includeThinkingInHistory)
        }
    }

    private func translateNonToolMessage(_ message: Message, includeThinkingInHistory: Bool) -> [String: Any] {
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
            let thinking = includeThinkingInHistory ? split.thinking : ""
            let content = assistantContent(visible: split.visible, thinking: thinking)
            if content.isEmpty, hasToolCalls {
                dict["content"] = NSNull()
            } else {
                dict["content"] = content
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
    }

    private func assistantContent(visible: String, thinking: String) -> String {
        guard !thinking.isEmpty else {
            return visible
        }

        if visible.isEmpty {
            return "<think>\(thinking)</think>"
        }

        return "<think>\(thinking)</think>\n\(visible)"
    }
}
