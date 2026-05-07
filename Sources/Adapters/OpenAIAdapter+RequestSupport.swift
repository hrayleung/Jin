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
            reasoningEnabled: reasoningEnabled
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

        OpenAIResponsesRequestSupport.applyContextCacheControls(to: &body, controls: controls)
        OpenAIResponsesRequestSupport.applySamplingControls(
            to: &body,
            controls: controls,
            supportsSamplingParameters: supportsSamplingParameters
        )
        if let maxTokens = controls.maxTokens {
            body["max_output_tokens"] = maxTokens
        }
        if let serviceTier = resolvedOpenAIServiceTier(from: controls) {
            body["service_tier"] = serviceTier
        }
        OpenAIResponsesRequestSupport.applyReasoningConfig(
            to: &body,
            controls: controls,
            providerType: providerConfig.type,
            modelID: modelID,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort
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

    func supportsNativePDF(_ modelID: String) -> Bool {
        JinModelSupport.supportsNativePDF(providerType: .openai, modelID: modelID)
    }

    func supportsCodeExecution(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: .openai, modelID: modelID)
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
