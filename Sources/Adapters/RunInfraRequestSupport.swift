import Foundation

extension RunInfraAdapter {
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

    /// Applies RunInfra Model APIs reasoning controls.
    ///
    /// Official chat-completions contract (2026-08-27):
    /// - `reasoning_effort` is the only honored spelling.
    /// - `"none"` turns thinking off, except on models that refuse disable.
    /// - A top-level `reasoning` object is removed before dispatch.
    /// - Vendor spellings (`enable_thinking`, `thinking`, …) have no effect.
    private func applyReasoning(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else { return }
        guard let reasoning = controls.reasoning else { return }

        let catalog = ModelCatalog.entry(for: modelID, provider: .runinfra)
        let reasoningType = catalog?.reasoningConfig?.type
        let canDisable = ModelSettingsResolver.defaultReasoningCanDisable(
            for: .runinfra,
            modelID: modelID,
            declaredEfforts: catalog?.reasoningConfig?.supportedEfforts
        )

        if reasoningType == .effort {
            let isDisabled = reasoning.enabled == false || reasoning.effort == .some(.none)
            if isDisabled {
                if canDisable {
                    body["reasoning_effort"] = "none"
                }
                return
            }

            let defaultEffort = catalog?.reasoningConfig?.defaultEffort ?? .medium
            let effort = ModelCapabilityRegistry.normalizedReasoningEffort(
                reasoning.effort ?? defaultEffort,
                for: .runinfra,
                modelID: modelID,
                declaredEfforts: catalog?.reasoningConfig?.supportedEfforts
            )
            if effort == .none {
                if canDisable {
                    body["reasoning_effort"] = "none"
                }
                return
            }
            body["reasoning_effort"] = effort.rawValue
            return
        }

        if reasoning.enabled == false, canDisable {
            body["reasoning_effort"] = "none"
        }
    }

    private func translateMessages(_ messages: [Message], modelID: String) throws -> [[String: Any]] {
        let supportsVision = modelSupportsVision(modelID)
        var remainingImages = supportsVision ? RunInfraVisionSupport.maxImagesPerRequest : 0
        return try translateMessagesToOpenAIFormat(messages) { message in
            try self.translateNonToolMessage(
                message,
                supportsVision: supportsVision,
                remainingImages: &remainingImages
            )
        }
    }

    private func translateNonToolMessage(
        _ message: Message,
        supportsVision: Bool,
        remainingImages: inout Int
    ) throws -> [String: Any] {
        let split = splitContentParts(
            message.content,
            separator: "\n",
            includeImages: supportsVision,
            imageUnsupportedMessage: supportsVision
                ? nil
                : "[Image attachment omitted: this RunInfra model does not accept image content parts.]"
        )

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if supportsVision, split.hasRichUserContent {
                dict["content"] = try translateVisionUserContent(
                    message.content,
                    remainingImages: &remainingImages
                )
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

            if let thinking = split.thinkingOrNil {
                dict["reasoning"] = thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    /// Forwards inline images until the documented per-request cap, then notes extras
    /// as text so the gateway does not 400 the whole completion.
    private func translateVisionUserContent(
        _ parts: [ContentPart],
        remainingImages: inout Int
    ) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var omitted = 0

        for part in parts {
            switch part {
            case .text(let text):
                out.append(["type": "text", "text": text])
            case .quote(let quote):
                out.append(["type": "text", "text": quote.quotedText])
            case .image(let image):
                guard remainingImages > 0 else {
                    omitted += 1
                    continue
                }
                if let urlString = try imageToURLString(image) {
                    remainingImages -= 1
                    out.append([
                        "type": "image_url",
                        "image_url": ["url": urlString],
                    ])
                }
            case .file(let file):
                out.append([
                    "type": "text",
                    "text": AttachmentPromptRenderer.fallbackText(for: file),
                ])
            case .audio, .video, .thinking, .redactedThinking:
                continue
            }
        }

        if omitted > 0 {
            out.append([
                "type": "text",
                "text": "[Omitted \(omitted) extra image(s): this RunInfra model accepts at most \(RunInfraVisionSupport.maxImagesPerRequest) images per request.]",
            ])
        }

        return out
    }

    private func modelSupportsVision(_ modelID: String) -> Bool {
        if let model = findConfiguredModel(in: providerConfig, for: modelID) {
            return ModelSettingsResolver.resolve(model: model, providerType: .runinfra)
                .capabilities.contains(.vision)
        }
        return ModelCatalog.entry(for: modelID, provider: .runinfra)?.capabilities.contains(.vision) == true
    }
}
