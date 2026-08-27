import Foundation

extension MakoraAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let canonicalID = MakoraModelSupport.canonicalModelID(for: modelID)

        var body: [String: Any] = [
            "model": canonicalID,
            "messages": try translateMessages(messages, modelID: canonicalID),
            "stream": streaming
        ]

        if streaming {
            body["stream_options"] = ["include_usage": true]
        }

        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
        if let maxTokens = controls.maxTokens {
            // omp-makora-provider's live `/v1/models` dump sets maxTokensField to
            // `max_completion_tokens` for every Makora chat model.
            body["max_completion_tokens"] = maxTokens
        }

        applyReasoning(to: &body, controls: controls, modelID: canonicalID)

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
            if MakoraModelSupport.disablesNativeToolChoice(canonicalID) {
                body["tool_choice"] = "none"
                body["skip_special_tokens"] = false
            }
            if MakoraModelSupport.usesToolStream(canonicalID) {
                body["tool_stream"] = true
            }
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL(MakoraModelSupport.chatCompletionsURL(baseURL: baseURL, modelID: canonicalID)),
            apiKey: apiKey,
            body: body,
            includeUserAgent: false
        )
    }

    private func applyReasoning(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        let format = MakoraModelSupport.thinkingFormat(for: modelID)
        guard format != .none else { return }

        let reasoning = controls.reasoning
        let isAlwaysOn = MakoraModelSupport.isAlwaysOnReasoningModel(modelID)
        let userDisabled = reasoning?.enabled == false
            || reasoning?.effort == ReasoningEffort.none
        let thinkingEnabled = isAlwaysOn || (reasoning != nil && !userDisabled)

        switch format {
        case .deepSeekFlash:
            body.removeValue(forKey: "thinking")
            body["include_reasoning"] = thinkingEnabled
            OpenAICompatibleReasoningSupport.mergeChatTemplateKwargs(
                into: &body,
                additional: ["thinking": thinkingEnabled]
            )
            if thinkingEnabled {
                applyReasoningEffortIfPresent(to: &body, controls: controls, modelID: modelID)
            }

        case .deepSeekPro:
            body.removeValue(forKey: "thinking")
            OpenAICompatibleReasoningSupport.mergeChatTemplateKwargs(
                into: &body,
                additional: ["thinking": thinkingEnabled]
            )
            if thinkingEnabled {
                applyReasoningEffortIfPresent(to: &body, controls: controls, modelID: modelID)
            }

        case .enableThinking:
            body.removeValue(forKey: "thinking")
            OpenAICompatibleReasoningSupport.mergeChatTemplateKwargs(
                into: &body,
                additional: ["enable_thinking": thinkingEnabled]
            )
            if thinkingEnabled {
                applyReasoningEffortIfPresent(to: &body, controls: controls, modelID: modelID)
            }

        case .gptOss:
            body.removeValue(forKey: "thinking")
            body["include_reasoning"] = true
            applyReasoningEffortIfPresent(
                to: &body,
                controls: controls,
                modelID: modelID,
                defaultEffort: .medium
            )

        case .none:
            break
        }
    }

    private func applyReasoningEffortIfPresent(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String,
        defaultEffort: ReasoningEffort? = nil
    ) {
        let resolved = resolvedReasoningConfig(for: modelID)
        guard resolved?.type == .effort else { return }

        let effort = ModelCapabilityRegistry.normalizedReasoningEffort(
            controls.reasoning?.effort ?? resolved?.defaultEffort ?? defaultEffort ?? .medium,
            for: .makora,
            modelID: modelID,
            declaredEfforts: resolved?.supportedEfforts
        )
        guard effort != .none else { return }
        body["reasoning_effort"] = effort.rawValue
    }

    private func resolvedReasoningConfig(for modelID: String) -> ModelReasoningConfig? {
        if let configuredModel = findConfiguredModel(in: providerConfig, for: modelID) {
            return ModelSettingsResolver.resolve(
                model: configuredModel,
                providerType: providerConfig.type
            ).reasoningConfig
        }
        return ModelCatalog.entry(for: modelID, provider: .makora)?.reasoningConfig
    }

    private func translateMessages(_ messages: [Message], modelID: String) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages) { message in
            try translateNonToolMessage(message, modelID: modelID)
        }
    }

    private func translateNonToolMessage(_ message: Message, modelID: String) throws -> [String: Any] {
        let split = splitContentParts(message.content, separator: "\n", includeImages: true, includeAudio: true)

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .assistant:
            if MakoraModelSupport.stripsToolCallsOnFollowUp(modelID),
               let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["content"] = MakoraToolCallRepair.glmXML(from: toolCalls, preceding: split.visible)
            } else {
                dict["content"] = split.visible
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
                }
            }
            if let thinking = split.thinkingOrNil {
                dict["reasoning_content"] = thinking
                dict["reasoning"] = thinking
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
