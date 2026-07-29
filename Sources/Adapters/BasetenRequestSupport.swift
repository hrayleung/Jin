import Foundation

extension BasetenAdapter {
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

        if streaming {
            body["stream_options"] = ["include_usage": true]
        }

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
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
            accept: nil,
            includeUserAgent: false
        )
    }

    /// Applies Baseten Model APIs reasoning controls.
    ///
    /// Official docs (2026-07-29):
    /// - Opt-in families use `chat_template_args: { enable_thinking: true/false }`.
    /// - Effort families use top-level `reasoning_effort` string.
    /// - Inkling only honors `reasoning_effort` (including `"none"` to disable).
    /// - Kimi K3 accepts either control; we send `reasoning_effort` (default max).
    private func applyReasoning(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else { return }
        guard let reasoning = controls.reasoning else { return }

        let lower = modelID.lowercased()

        if Self.chatTemplateToggleModelIDs.contains(lower) {
            // Toggle models: only `enabled` controls thinking. A nil effort must not
            // be treated as disable (effort defaults to nil on ReasoningControls).
            let thinkingOn = reasoning.enabled != false
            mergeChatTemplateArgs(into: &body, enableThinking: thinkingOn)
            // GLM 5.2 family also supports reasoning_effort none/high/max when thinking is on.
            if Self.glm52EffortModelIDs.contains(lower), thinkingOn {
                let effort = ModelCapabilityRegistry.normalizedReasoningEffort(
                    reasoning.effort ?? .high,
                    for: .baseten,
                    modelID: modelID
                )
                body["reasoning_effort"] = mapEffortWireValue(effort)
            }
            return
        }

        // Effort-controlled families (DeepSeek V4 Pro, Inkling, Kimi K3, GPT-OSS 120B, …)
        let isDisabled = reasoning.enabled == false
            || reasoning.effort == .some(.none)
        if isDisabled {
            body["reasoning_effort"] = "none"
            return
        }

        let defaultEffort = ModelCatalog.entry(for: modelID, provider: .baseten)?
            .reasoningConfig?
            .defaultEffort ?? .medium
        let effort = ModelCapabilityRegistry.normalizedReasoningEffort(
            reasoning.effort ?? defaultEffort,
            for: .baseten,
            modelID: modelID
        )
        body["reasoning_effort"] = mapEffortWireValue(effort)
    }

    private func mapEffortWireValue(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return "none"
        case .minimal:
            return "minimal"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        case .max:
            return "max"
        }
    }

    private func mergeChatTemplateArgs(into body: inout [String: Any], enableThinking: Bool) {
        var args = (body["chat_template_args"] as? [String: Any]) ?? [:]
        args["enable_thinking"] = enableThinking
        body["chat_template_args"] = args
    }

    private func translateMessages(_ messages: [Message]) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages, translateNonToolMessage: translateNonToolMessage)
    }

    private func translateNonToolMessage(_ message: Message) throws -> [String: Any] {
        let split = splitContentParts(message.content, includeImages: true, includeAudio: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

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

    /// Models that enable thinking only via `chat_template_args.enable_thinking`.
    private static let chatTemplateToggleModelIDs: Set<String> = [
        "moonshotai/kimi-k2.6",
        "moonshotai/kimi-k2.7-code",
        "zai-org/glm-4.7",
        "zai-org/glm-5.2",
        "zai-org/glm-5.2-fast",
        "nvidia/nvidia-nemotron-3-ultra-550b-a55b",
    ]

    /// GLM 5.2 family also accepts top-level `reasoning_effort` (none/high/max).
    private static let glm52EffortModelIDs: Set<String> = [
        "zai-org/glm-5.2",
        "zai-org/glm-5.2-fast",
    ]
}
