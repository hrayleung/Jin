import Foundation

extension OpenRouterAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let imageGenerationModel = isImageGenerationModel(modelID)
        let lowerModelID = modelID.lowercased()
        let omitsSamplingParameters = lowerModelID == "openai/gpt-5.4-image-2"
        let unsupportedSamplingParameterKeys: Set<String> = [
            "temperature",
            "top_p",
            "top_k",
            "min_p",
            "repetition_penalty"
        ]

        var body: [String: Any] = [
            "model": modelID,
            "messages": try translateMessages(messages),
            "stream": streaming
        ]

        let requestShape = ModelCapabilityRegistry.requestShape(for: providerConfig.type, modelID: modelID)
        let shouldOmitSamplingControls = applyReasoning(
            to: &body,
            controls: controls,
            modelID: modelID,
            requestShape: requestShape
        )

        if !shouldOmitSamplingControls && !omitsSamplingParameters {
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

        if imageGenerationModel {
            applyImageGeneration(to: &body, controls: controls)
        }

        if controls.webSearch?.enabled == true, modelSupportsWebSearch(for: modelID) {
            var plugins = body["plugins"] as? [[String: Any]] ?? []
            plugins.append(["id": "web"])
            body["plugins"] = plugins
        }

        if !imageGenerationModel,
           supportsClientFunctionTools(modelID: modelID),
           !tools.isEmpty,
           let functionTools = translateTools(tools) as? [[String: Any]] {
            body["tools"] = functionTools
        }

        for (key, value) in controls.providerSpecific {
            if omitsSamplingParameters,
               unsupportedSamplingParameterKeys.contains(key.lowercased()) {
                continue
            }
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            body: body,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )
    }

    func isVideoGenerationModel(_ modelID: String) -> Bool {
        if let model = findConfiguredModel(in: providerConfig, for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
            if resolved.capabilities.contains(.videoGeneration) {
                return true
            }
        }

        return ModelCatalog.entry(for: modelID, provider: .openrouter)?.capabilities.contains(.videoGeneration) == true
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
                dict["reasoning"] = split.thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = ""
        }

        return dict
    }

    private func applyImageGeneration(
        to body: inout [String: Any],
        controls: GenerationControls
    ) {
        let responseMode = controls.imageGeneration?.responseMode ?? .textAndImage
        body["modalities"] = openRouterModalities(for: responseMode)

        if let seed = controls.imageGeneration?.seed {
            body["seed"] = seed
        }
    }

    private func openRouterModalities(for responseMode: ImageResponseMode) -> [String] {
        switch responseMode {
        case .textAndImage:
            return ["text", "image"]
        case .imageOnly:
            return ["image"]
        }
    }

    /// OpenRouter-specific reasoning application. Adds `include_reasoning` field
    /// on top of the standard OpenAI-compatible reasoning logic.
    private func applyReasoning(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String,
        requestShape: ModelRequestShape
    ) -> Bool {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else {
            return false
        }
        guard let reasoning = controls.reasoning else { return false }

        switch requestShape {
        case .openAIResponses, .openAICompatible:
            if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                body["include_reasoning"] = false
                body["reasoning"] = ["effort": "none"]
                return false
            }

            let effort = reasoning.effort ?? .medium
            body["include_reasoning"] = true
            body["reasoning"] = [
                "effort": OpenAICompatibleReasoningSupport.mapReasoningEffort(
                    effort,
                    providerConfig: providerConfig,
                    modelID: modelID
                )
            ]
            return requestShape == .openAIResponses

        case .anthropic, .gemini:
            return OpenAICompatibleReasoningSupport.applyReasoning(
                to: &body,
                controls: controls,
                providerConfig: providerConfig,
                modelID: modelID,
                requestShape: requestShape
            )
        }
    }

    private func modelSupportsWebSearch(for modelID: String) -> Bool {
        guard let model = findConfiguredModel(in: providerConfig, for: modelID) else {
            return ModelCapabilityRegistry.supportsWebSearch(
                for: providerConfig.type,
                modelID: modelID
            )
        }

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
        return resolved.supportsWebSearch
    }

    private func supportsClientFunctionTools(modelID: String) -> Bool {
        guard let model = findConfiguredModel(in: providerConfig, for: modelID) else {
            return ModelCatalog.entry(for: modelID, provider: .openrouter)?.capabilities.contains(.toolCalling) == true
        }

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
        return resolved.capabilities.contains(.toolCalling)
    }

    private func isImageGenerationModel(_ modelID: String) -> Bool {
        if let model = findConfiguredModel(in: providerConfig, for: modelID) {
            let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerConfig.type)
            if resolved.capabilities.contains(.imageGeneration) {
                return true
            }
        }

        return ModelCatalog.entry(for: modelID, provider: .openrouter)?.capabilities.contains(.imageGeneration) == true
    }
}
