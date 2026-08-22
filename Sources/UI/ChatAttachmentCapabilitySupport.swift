import Foundation

extension ChatModelCapabilitySupport {
    static func isImageGenerationModelID(
        providerType: ProviderType?,
        lowerModelID: String,
        openAIImageGenerationModelIDs: Set<String>,
        xAIImageGenerationModelIDs: Set<String>,
        geminiImageGenerationModelIDs: Set<String>
    ) -> Bool {
        switch providerType {
        case .openai, .openaiWebSocket:
            return openAIImageGenerationModelIDs.contains(lowerModelID)
        case .xai:
            return xAIImageGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return geminiImageGenerationModelIDs.contains(lowerModelID)
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .baseten, .anthropic, .claudeManagedAgents, .perplexity,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI,
             .fireworks, .cerebras, .sambanova, .databricks, .modal, .morphllm, .opencodeGo, .router, .zyphra, .meta, .kimiForCoding, .none:
            return false
        }
    }

    static func isVideoGenerationModelID(
        providerType: ProviderType?,
        lowerModelID: String,
        xAIVideoGenerationModelIDs: Set<String>,
        googleVideoGenerationModelIDs: Set<String>
    ) -> Bool {
        switch providerType {
        case .xai:
            return xAIVideoGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return googleVideoGenerationModelIDs.contains(lowerModelID)
        default:
            return false
        }
    }

    static func supportsNativePDF(
        supportsMediaGenerationControl: Bool,
        providerType: ProviderType?,
        resolvedModelSettings: ResolvedModelSettings?,
        lowerModelID: String
    ) -> Bool {
        guard !supportsMediaGenerationControl else { return false }
        guard let providerType else { return false }
        guard providerType.supportsNativePDFUpload else { return false }

        let catalogAllows = resolvedModelSettings?.capabilities.contains(.nativePDF) == true
            || JinModelSupport.supportsNativePDF(providerType: providerType, modelID: lowerModelID)
        guard catalogAllows else { return false }

        return adapterCanSendNativePDF(providerType: providerType, modelID: lowerModelID)
    }

    /// Adapter-side send check. Catalog `.nativePDF` is not enough when the
    /// translator cannot emit `application/pdf` (Gemini AI Studio 2.5).
    /// Anthropic / Claude Managed persist `.nativePDF` on custom models, but
    /// `AnthropicAdapter` only emits document blocks for catalog IDs — keep
    /// the UI on that same predicate so Native is not offered as a stub.
    static func adapterCanSendNativePDF(providerType: ProviderType, modelID: String) -> Bool {
        switch providerType {
        case .gemini:
            return GeminiModelConstants.supportsNativePDF(modelID)
        case .vertexai:
            return GeminiModelConstants.supportsVertexNativePDF(modelID)
        case .anthropic, .claudeManagedAgents:
            return JinModelSupport.supportsNativePDF(providerType: providerType, modelID: modelID)
        case .openai, .openaiWebSocket, .xai, .meta:
            return true
        case .opencodeGo:
            // Responses-routed Muse Spark IDs emit inline `input_file`. Exact IDs from
            // live `/models` — a near-miss must not light Native PDF on /chat/completions.
            return ModelCapabilityRegistry.isOpenCodeGoMuseSparkModelID(modelID.lowercased())
        default:
            return false
        }
    }

    static func supportsPagesAsImages(supportsNativePDF: Bool, supportsVision: Bool) -> Bool {
        supportsVision && !supportsNativePDF
    }

    static func supportsVision(
        resolvedModelSettings: ResolvedModelSettings?,
        supportsImageGenerationControl: Bool,
        supportsVideoGenerationControl: Bool
    ) -> Bool {
        resolvedModelSettings?.capabilities.contains(.vision) == true
            || supportsImageGenerationControl
            || supportsVideoGenerationControl
    }

    static func isMistralTranscriptionOnlyModelID(
        providerType: ProviderType?,
        lowerModelID: String,
        mistralTranscriptionOnlyModelIDs: Set<String>
    ) -> Bool {
        providerType == .mistral
            && mistralTranscriptionOnlyModelIDs.contains(lowerModelID)
    }

    static func supportsAudioInput(
        isMistralTranscriptionOnlyModelID: Bool,
        resolvedModelSettings: ResolvedModelSettings?,
        supportsMediaGenerationControl: Bool,
        providerType: ProviderType?,
        lowerModelID: String,
        openAIAudioInputModelIDs: Set<String>,
        mistralAudioInputModelIDs: Set<String>,
        geminiAudioInputModelIDs: Set<String>,
        compatibleAudioInputModelIDs: Set<String>,
        fireworksAudioInputModelIDs: Set<String>
    ) -> Bool {
        if isMistralTranscriptionOnlyModelID {
            return false
        }

        if resolvedModelSettings?.capabilities.contains(.audio) == true {
            return true
        }

        if supportsMediaGenerationControl {
            return false
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            return openAIAudioInputModelIDs.contains(lowerModelID)
        case .mistral:
            return mistralAudioInputModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return geminiAudioInputModelIDs.contains(lowerModelID)
        case .githubCopilot, .openrouter, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .deepinfra, .together, .baseten:
            return compatibleAudioInputModelIDs.contains(lowerModelID)
        case .mimoTokenPlanOpenAI:
            return resolvedModelSettings?.capabilities.contains(.audio) == true
        case .fireworks:
            return fireworksAudioInputModelIDs.contains(lowerModelID)
        // Router: every model in its live catalog reports `modalities.input` as
        // text (+image) only — no audio anywhere in the fleet.
        case .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .xai, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .cerebras, .sambanova, .databricks, .modal, .morphllm, .opencodeGo, .router, .zyphra, .meta, .kimiForCoding, .none:
            return false
        }
    }

    static func supportsVideoInput(
        resolvedModelSettings: ResolvedModelSettings?,
        supportsMediaGenerationControl: Bool,
        providerType: ProviderType?,
        lowerModelID: String
    ) -> Bool {
        if resolvedModelSettings?.capabilities.contains(.videoInput) == true {
            return true
        }

        guard !supportsMediaGenerationControl else { return false }

        // Catalog fallback for any provider, not just MiMo: a model persisted before its
        // record gained `.videoInput` carries stale capabilities, and `resolvedModelSettings`
        // is nil on the paths that never resolved one. Keeping this MiMo-only left every
        // other provider's video-capable models looking text/image-only in the composer.
        guard let providerType else { return false }
        return ModelCatalog.entry(
            for: lowerModelID,
            provider: providerType
        )?.capabilities.contains(.videoInput) == true
    }

    static func supportsImageGenerationWebSearch(
        supportsImageGenerationControl: Bool,
        resolvedModelSettings: ResolvedModelSettings?,
        providerType: ProviderType?,
        conversationModelID: String
    ) -> Bool {
        guard supportsImageGenerationControl else { return false }
        if let resolvedModelSettings {
            return resolvedModelSettings.supportsWebSearch
        }
        return ModelCapabilityRegistry.supportsWebSearch(for: providerType, modelID: conversationModelID)
    }
}
