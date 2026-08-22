import Foundation

extension OpenAIAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> URLRequest {
        let supportsNativeFileInput = supportsNativePDF(modelID)
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let codeExecutionEnabled = controls.codeExecution?.enabled == true && supportsCodeExecution(modelID)
        let reasoningEffort = (controls.reasoning?.enabled == true) ? controls.reasoning?.effort : nil
        let reasoningEnabled = (reasoningEffort ?? .none) != .none
        let supportsSamplingParameters = supportsOpenAIResponsesSamplingParameters(
            modelID: modelID,
            reasoningEnabled: reasoningEnabled,
            providerType: providerConfig.type
        )
        let webSearchEnabled = controls.webSearch?.enabled == true && supportsWebSearch(modelID)

        var body: [String: Any] = [
            "model": modelID,
            "input": try await translateInput(
                messages,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            ),
            "stream": streaming
        ]

        if usesNativeOpenAIPlatform {
            OpenAIResponsesRequestSupport.applyContextCacheControls(to: &body, controls: controls)
        }
        OpenAIResponsesRequestSupport.applySamplingControls(
            to: &body,
            controls: controls,
            supportsSamplingParameters: supportsSamplingParameters
        )
        // Muse Spark documents temperature XOR top_p (dev.meta.ai). When both knobs are
        // set, keep temperature — the same rule MetaAdapter applies on the native host.
        if ModelCapabilityRegistry.isMetaMuseSparkModelID(modelID.lowercased()),
           body["temperature"] != nil {
            body.removeValue(forKey: "top_p")
        }
        if let maxTokens = controls.maxTokens {
            // Router's Anthropic-routed models reject a ceiling that leaves no room for
            // the thinking budget, so raise it to the documented minimum rather than
            // letting the send 400. No-op for every other provider and model.
            if RouterRequestSupport.requiresAnthropicThinkingHeadroom(
                providerType: providerConfig.type,
                modelID: modelID,
                reasoningEnabled: reasoningEnabled
            ) {
                body["max_output_tokens"] = max(
                    maxTokens,
                    RouterRequestSupport.minimumMaxOutputTokensWithReasoning
                )
            } else {
                body["max_output_tokens"] = maxTokens
            }
        }
        if usesNativeOpenAIPlatform, let serviceTier = resolvedOpenAIServiceTier(from: controls) {
            body["service_tier"] = serviceTier
        }
        OpenAIResponsesRequestSupport.applyReasoningConfig(
            to: &body,
            controls: controls,
            providerType: providerConfig.type,
            modelID: modelID,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            // Gateways that publish a per-model effort band and enforce it (Router)
            // record it on the model at fetch time. Prefer it over the static
            // allowlists, which cannot know a model newer than this build.
            declaredEfforts: declaredReasoningEfforts(for: modelID)
        )

        let functionTools = tools.isEmpty ? [] : (translateTools(tools) as? [[String: Any]] ?? [])
        let toolObjects = OpenAIResponsesRequestSupport.toolObjects(
            controls: controls,
            functionTools: functionTools,
            supportsWebSearch: supportsWebSearch(modelID),
            codeExecutionEnabled: codeExecutionEnabled
        )
        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        OpenAIResponsesRequestSupport.applyProviderSpecificOverrides(
            to: &body,
            controls: controls,
            providerType: providerConfig.type,
            supportsSamplingParameters: supportsSamplingParameters
        )
        OpenAIResponsesRequestSupport.applyRequiredIncludeFields(
            to: &body,
            webSearchEnabled: webSearchEnabled,
            codeExecutionEnabled: codeExecutionEnabled
        )

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/responses"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            includeUserAgent: false
        )
    }

    /// True only when this adapter is driving the real OpenAI platform. `OpenAIAdapter` is
    /// also used as a delegate for gateways that expose the Responses API on their own host
    /// (OpenCode Go's `/zen/go/v1/responses`), where OpenAI-platform-only wire fields are
    /// rejected as unknown input.
    /// The effort band the provider reported for this model when its catalog was
    /// fetched, if any. Nil for every model whose band is only known statically —
    /// which is the whole bundled catalog, so this is a no-op on the OpenAI path.
    func declaredReasoningEfforts(for modelID: String) -> [ReasoningEffort]? {
        providerConfig.models
            .first { $0.id == modelID }?
            .reasoningConfig?
            .supportedEfforts
    }

    var usesNativeOpenAIPlatform: Bool {
        providerConfig.type == .openai || providerConfig.type == .openaiWebSocket
    }

    func supportsNativePDF(_ modelID: String) -> Bool {
        JinModelSupport.supportsNativePDF(providerType: providerConfig.type, modelID: modelID)
    }

    func supportsCodeExecution(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: providerConfig.type, modelID: modelID)
    }

    func supportsWebSearch(_ modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    func shouldRouteToChatCompletionsForAudio(messages: [Message], modelID: String) -> Bool {
        guard isOpenAIAudioInputModelID(modelID.lowercased()) else {
            return false
        }

        for message in messages where message.role != .tool {
            if message.content.contains(where: { part in
                if case .audio = part { return true }
                return false
            }) {
                return true
            }
        }

        return false
    }
}
