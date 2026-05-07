import Foundation

extension TogetherAdapter {
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

        applyReasoning(to: &body, controls: controls, modelID: modelID)

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

    private func applyReasoning(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else { return }
        guard let reasoning = controls.reasoning else { return }

        switch resolvedReasoningType(for: modelID) {
        case .toggle:
            body["reasoning"] = ["enabled": reasoning.enabled]

        case .effort:
            guard reasoning.enabled else { return }
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

        case .budget, .none, .noneSet:
            break
        }
    }

    private func resolvedReasoningType(for modelID: String) -> TogetherReasoningType {
        if let configuredModel = findConfiguredModel(in: providerConfig, for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: configuredModel, providerType: providerConfig.type)
            guard let reasoningType = resolved.reasoningConfig?.type else { return .noneSet }
            return TogetherReasoningType(reasoningType)
        }

        if let catalogType = ModelCatalog.entry(for: modelID, provider: .together)?.reasoningConfig?.type {
            return TogetherReasoningType(catalogType)
        }

        return .noneSet
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
            if let thinking = split.thinkingOrNil {
                dict["reasoning"] = thinking
            }

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

private enum TogetherReasoningType {
    case toggle
    case effort
    case budget
    case none
    case noneSet

    init(_ raw: ReasoningConfigType) {
        switch raw {
        case .toggle:
            self = .toggle
        case .effort:
            self = .effort
        case .budget:
            self = .budget
        case .none:
            self = .none
        }
    }
}
