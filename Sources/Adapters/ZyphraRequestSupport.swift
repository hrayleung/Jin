import Foundation

extension ZyphraAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let resolvedModelID = ZyphraAdapter.canonicalModelID(for: modelID)

        var body: [String: Any] = [
            "model": resolvedModelID,
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

    private func resolvedReasoningType(for modelID: String) -> ZyphraReasoningType {
        if let configuredModel = findConfiguredModel(in: providerConfig, for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: configuredModel, providerType: providerConfig.type)
            guard let reasoningType = resolved.reasoningConfig?.type else { return .noneSet }
            return ZyphraReasoningType(reasoningType)
        }

        if let catalogType = ModelCatalog.entry(for: modelID, provider: .zyphra)?.reasoningConfig?.type {
            return ZyphraReasoningType(catalogType)
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

extension ZyphraAdapter {
    /// Maps known legacy/aliased model IDs to the exact strings Zyphra's API expects.
    /// Existing conversation threads (and any user-provided typos) get corrected at
    /// request time so they don't 404. New threads created from the live `/models`
    /// catalog already use the canonical IDs and pass through unchanged.
    static func canonicalModelID(for modelID: String) -> String {
        switch modelID.lowercased() {
        case "zyphra/zaya1-8b":
            return "zyphra/ZAYA1-8B"
        case "zai-org/glm-5.1", "zai-org/glm-5.1-fp8":
            return "zai-org/GLM-5.1-FP8"
        case "moonshotai/kimi-k2.6":
            return "moonshotai/Kimi-K2.6"
        case "deepseek-ai/deepseek-v3.2":
            return "deepseek-ai/DeepSeek-V3.2"
        default:
            return modelID
        }
    }
}

private enum ZyphraReasoningType {
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
