import Foundation

extension DatabricksAdapter {
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

        if streaming {
            // Request a trailing usage chunk so input/output token counts populate.
            body["stream_options"] = ["include_usage": true]
        }

        // OpenAI GPT-5 and o-series reasoning models only accept the default temperature/top_p
        // (value 1). Sending a custom value returns a 400 (`unsupported_value`). This applies to
        // both the AI Gateway OpenAI surface and Databricks-hosted `databricks-gpt-5-*` endpoints.
        if !modelRejectsCustomSampling(modelID) {
            if let temperature = controls.temperature {
                body["temperature"] = temperature
            }
            if let topP = controls.topP {
                body["top_p"] = topP
            }
        }
        if let maxTokens = controls.maxTokens {
            // The AI Gateway OpenAI surface forwards to the native OpenAI API, whose GPT-5 /
            // o-series models reject `max_tokens` and require `max_completion_tokens`.
            body[isOpenAIGateway ? "max_completion_tokens" : "max_tokens"] = maxTokens
        }

        applyReasoning(to: &body, controls: controls, modelID: modelID)

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        var additionalHeaders: [String: String] = [:]
        if isOpenAIGateway, let service = gatewayProviderService {
            additionalHeaders[DatabricksGateway.modelProviderServiceHeader] = service
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL(chatCompletionsURLString),
            apiKey: apiKey,
            body: body,
            additionalHeaders: additionalHeaders
        )
    }

    /// Databricks normalizes reasoning across model families to `reasoning_effort`
    /// (`low`/`medium`/`high`). When reasoning is disabled we omit the field so the model
    /// falls back to its server-side default.
    /// OpenAI GPT-5 / o-series reasoning models reject any non-default `temperature`/`top_p`.
    /// `gpt-4o` and other non-reasoning models still accept custom sampling.
    private func modelRejectsCustomSampling(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower.contains("gpt-5")
            || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4")
            || lower.contains("/o1") || lower.contains("/o3") || lower.contains("/o4")
            || lower.contains("-o1") || lower.contains("-o3") || lower.contains("-o4")
    }

    private func applyReasoning(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else { return }
        guard let reasoning = controls.reasoning, reasoning.enabled else { return }

        let effort = ModelCapabilityRegistry.normalizedReasoningEffort(
            reasoning.effort ?? .medium,
            for: providerConfig.type,
            modelID: modelID
        )
        switch effort {
        case .none, .minimal, .low:
            body["reasoning_effort"] = "low"
        case .medium:
            body["reasoning_effort"] = "medium"
        case .high, .xhigh, .max:
            body["reasoning_effort"] = "high"
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
                // Databricks chat endpoints accept image_url but not audio input; drop audio
                // parts rather than emitting an input_audio block the endpoint would reject.
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
            if let thinking = split.thinkingOrNil {
                dict["reasoning"] = thinking
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
