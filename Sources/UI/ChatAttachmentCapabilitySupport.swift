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
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .anthropic, .claudeManagedAgents, .perplexity,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
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

        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .claudeManagedAgents, .perplexity, .xai, .gemini, .vertexai:
            break
        case .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo,
             .zyphra:
            return false
        }

        if resolvedModelSettings?.capabilities.contains(.nativePDF) == true {
            return true
        }

        return JinModelSupport.supportsNativePDF(providerType: providerType, modelID: lowerModelID)
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
        case .githubCopilot, .openrouter, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .deepinfra, .together:
            return compatibleAudioInputModelIDs.contains(lowerModelID)
        case .mimoTokenPlanOpenAI:
            return resolvedModelSettings?.capabilities.contains(.audio) == true
        case .fireworks:
            return fireworksAudioInputModelIDs.contains(lowerModelID)
        case .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .xai, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .mimoTokenPlanAnthropic, .cerebras, .sambanova, .morphllm, .opencodeGo, .zyphra, .none:
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
        guard providerType == .mimoTokenPlanOpenAI else { return false }

        return ModelCatalog.modelInfo(
            for: lowerModelID,
            provider: .mimoTokenPlanOpenAI
        ).capabilities.contains(.videoInput)
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
