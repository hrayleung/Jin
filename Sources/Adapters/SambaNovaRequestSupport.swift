import Foundation

extension SambaNovaAdapter {
    func buildRequest(
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

        if !isAlwaysOnReasoningModel(lower) {
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

        applyReasoningControls(to: &body, controls: controls, lowerModelID: lower)

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

    private func applyReasoningControls(
        to body: inout [String: Any],
        controls: GenerationControls,
        lowerModelID: String
    ) {
        guard let reasoning = controls.reasoning else { return }

        if lowerModelID == "gpt-oss-120b" {
            if reasoning.enabled == false {
                body["reasoning_effort"] = "low"
            } else if let effort = reasoning.effort {
                body["reasoning_effort"] = mapReasoningEffort(effort)
            }
            return
        }

        if usesThinkingTemplateKwargs(lowerModelID) {
            body["chat_template_kwargs"] = ["enable_thinking": reasoning.enabled != false]
        }
    }

    private func isAlwaysOnReasoningModel(_ lowerModelID: String) -> Bool {
        lowerModelID.contains("deepseek-r1")
    }

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
            let content: String
            if split.thinking.isEmpty {
                content = split.visible
            } else if split.visible.isEmpty {
                content = "<think>\(split.thinking)</think>"
            } else {
                content = "<think>\(split.thinking)</think>\n\(split.visible)"
            }

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
}
