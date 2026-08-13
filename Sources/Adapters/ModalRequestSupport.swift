import Foundation

extension ModalAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let route = ModalEndpointSupport.requestRoute(
            modelID: modelID,
            configured: findConfiguredModel(in: providerConfig, for: modelID),
            providerBaseURL: baseURL
        )
        var body: [String: Any] = [
            "model": route.wireModelID,
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

        let headers = ModalAdapter.authHeaders(for: apiKey)
        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(route.baseURL)/chat/completions"),
            apiKey: apiKey,
            authHeader: headers.auth,
            body: body,
            accept: nil,
            additionalHeaders: headers.additional,
            includeUserAgent: false
        )
    }

    /// Applies Modal reasoning controls.
    ///
    /// Modal serves open weights on stock vLLM behind its own proxy, so the only
    /// reasoning control that is part of the OpenAI schema is the top-level
    /// `reasoning_effort` string. Send it only when the user actually chose an
    /// effort — a strict gateway rejects request keys it doesn't model, and
    /// omitting the key is what "leave it to the engine default" means here.
    /// Engine-specific switches such as `chat_template_kwargs` remain reachable
    /// through `controls.providerSpecific`.
    private func applyReasoning(to body: inout [String: Any], controls: GenerationControls, modelID: String) {
        let configured = findConfiguredModel(in: providerConfig, for: modelID)
        let capabilityID = configured.map { ModalEndpointSupport.catalogModelID(for: $0) } ?? modelID
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else { return }
        guard let reasoning = controls.reasoning else { return }

        if reasoning.enabled == false || reasoning.effort == .some(.none) {
            // Only send `none` when the model actually accepts it. Qwen3.8-2.4T-A95B
            // requires thinking on every turn (HF: "thinking cannot be disabled");
            // omitting the key leaves the engine default (`xhigh`).
            let supported = ModelCapabilityRegistry.supportedReasoningEfforts(
                for: .modal,
                modelID: capabilityID
            )
            if supported.contains(.none) {
                body["reasoning_effort"] = ReasoningEffort.none.rawValue
            }
            return
        }

        guard let requestedEffort = reasoning.effort else { return }

        let effort = ModelCapabilityRegistry.normalizedReasoningEffort(
            requestedEffort,
            for: .modal,
            modelID: capabilityID
        )
        // ReasoningEffort raw values are the lowercase API labels (none…max).
        body["reasoning_effort"] = effort.rawValue
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
}
