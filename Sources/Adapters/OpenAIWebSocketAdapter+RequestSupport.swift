import Foundation

extension OpenAIWebSocketAdapter {
    func buildResponsePayload(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        previousResponseID: String?
    ) throws -> [String: Any] {
        let supportsNativeFileInput = supportsNativePDF(modelID)
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native

        var body: [String: Any] = [
            "model": modelID,
            "input": try translateInput(
                messages,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            ),
        ]

        if let previousResponseID {
            body["previous_response_id"] = previousResponseID
        }

        OpenAIResponsesRequestSupport.applyContextCacheControls(to: &body, controls: controls)

        let reasoningEffort = (controls.reasoning?.enabled == true) ? controls.reasoning?.effort : nil
        let reasoningEnabled = (reasoningEffort ?? .none) != .none
        let supportsSamplingParameters = supportsOpenAIResponsesSamplingParameters(
            modelID: modelID,
            reasoningEnabled: reasoningEnabled
        )

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

        let codeExecutionEnabled = controls.codeExecution?.enabled == true && supportsCodeExecution(modelID)
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
            webSearchEnabled: controls.webSearch?.enabled == true && supportsWebSearch(modelID),
            codeExecutionEnabled: codeExecutionEnabled
        )

        return body
    }

    func isImageGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.imageGeneration) == true {
            return true
        }
        return OpenAIImageModelSupport.isImageGenerationModel(modelID)
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

    func supportsAudioInputModelID(_ lowerModelID: String) -> Bool {
        isOpenAIAudioInputModelID(lowerModelID)
    }

    func shouldRouteToChatCompletionsForAudio(messages: [Message], modelID: String) -> Bool {
        guard supportsAudioInputModelID(modelID.lowercased()) else {
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
