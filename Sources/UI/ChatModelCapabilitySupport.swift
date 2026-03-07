import Foundation

enum ChatModelCapabilitySupport {
    static func resolvedModelInfo(
        modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> ModelInfo? {
        let models = availableModels ?? providerEntity?.allModels ?? []
        return ProviderModelAliasResolver.resolvedModel(
            for: modelID,
            providerType: providerType,
            availableModels: models
        )
    }

    static func effectiveModelID(
        modelID: String,
        providerEntity: ProviderConfigEntity?,
        providerType: ProviderType?,
        availableModels: [ModelInfo]? = nil
    ) -> String {
        let models = availableModels ?? providerEntity?.allModels ?? []
        return ProviderModelAliasResolver.resolvedModelID(
            for: modelID,
            providerType: providerType,
            availableModels: models
        )
    }

    static func normalizedSelectedModelInfo(
        _ model: ModelInfo,
        providerType: ProviderType?
    ) -> ModelInfo {
        guard providerType == .fireworks else { return model }
        return normalizedFireworksModelInfo(model)
    }

    static func normalizedFireworksModelInfo(_ model: ModelInfo) -> ModelInfo {
        let canonicalID = fireworksCanonicalModelID(model.id)
        var caps = model.capabilities
        var contextWindow = model.contextWindow
        var reasoningConfig = model.reasoningConfig
        var name = model.name
        let defaultReasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)

        switch canonicalID {
        case "kimi-k2p5":
            caps.insert(.vision)
            caps.insert(.reasoning)
            contextWindow = 262_100
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "Kimi K2.5" }
        case "qwen3-omni-30b-a3b-instruct", "qwen3-omni-30b-a3b-thinking":
            caps.insert(.vision)
            caps.insert(.audio)
        case "qwen3-asr-4b", "qwen3-asr-0.6b":
            caps.insert(.audio)
        case "glm-5":
            caps.insert(.reasoning)
            contextWindow = 202_800
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "GLM-5" }
        case "glm-4p7":
            caps.insert(.reasoning)
            contextWindow = 202_800
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "GLM-4.7" }
        case "minimax-m2p5":
            caps.insert(.reasoning)
            contextWindow = 196_600
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "MiniMax M2.5" }
        case "minimax-m2p1":
            caps.insert(.reasoning)
            contextWindow = 204_800
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "MiniMax M2.1" }
        case "minimax-m2":
            caps.insert(.reasoning)
            contextWindow = 196_600
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "MiniMax M2" }
        default:
            break
        }

        return ModelInfo(
            id: model.id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            reasoningConfig: reasoningConfig,
            overrides: model.overrides,
            catalogMetadata: model.catalogMetadata,
            isEnabled: model.isEnabled
        )
    }

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
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .anthropic, .perplexity,
             .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
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
        case .openai, .openaiWebSocket, .anthropic, .perplexity, .xai, .gemini, .vertexai:
            break
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan,
             .fireworks, .cerebras, .sambanova:
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
        case .fireworks:
            return fireworksAudioInputModelIDs.contains(lowerModelID)
        case .anthropic, .perplexity, .groq, .cohere, .xai, .deepseek, .zhipuCodingPlan,
             .cerebras, .sambanova, .codexAppServer, .none:
            return false
        }
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

    static func supportsCurrentModelImageSizeControl(lowerModelID: String) -> Bool {
        lowerModelID == "gemini-3-pro-image-preview"
            || lowerModelID == "gemini-3.1-flash-image-preview"
    }

    static func supportedCurrentModelImageAspectRatios(lowerModelID: String) -> [ImageAspectRatio] {
        if lowerModelID == "gemini-3.1-flash-image-preview" {
            return ImageAspectRatio.nanoBanana2SupportedCases
        }
        return ImageAspectRatio.defaultSupportedCases
    }

    static func supportedCurrentModelImageSizes(lowerModelID: String) -> [ImageOutputSize] {
        if lowerModelID == "gemini-3.1-flash-image-preview" {
            return ImageOutputSize.nanoBanana2SupportedCases
        }
        return ImageOutputSize.defaultSupportedCases
    }

    static func isImageGenerationConfigured(providerType: ProviderType?, controls: GenerationControls) -> Bool {
        if providerType == .xai {
            return !(controls.xaiImageGeneration?.isEmpty ?? true)
        }
        if providerType == .openai || providerType == .openaiWebSocket {
            return !(controls.openaiImageGeneration?.isEmpty ?? true)
        }
        return !(controls.imageGeneration?.isEmpty ?? true)
    }

    static func imageGenerationBadgeText(
        supportsImageGenerationControl: Bool,
        providerType: ProviderType?,
        controls: GenerationControls,
        isImageGenerationConfigured: Bool
    ) -> String? {
        guard supportsImageGenerationControl else { return nil }

        if providerType == .xai {
            if let ratio = controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio {
                return ratio.displayName
            }
            if let count = controls.xaiImageGeneration?.count, count > 1 {
                return "x\(count)"
            }
            return isImageGenerationConfigured ? "On" : nil
        }

        if providerType == .openai || providerType == .openaiWebSocket {
            if let size = controls.openaiImageGeneration?.size {
                return size.displayName
            }
            if let quality = controls.openaiImageGeneration?.quality {
                return quality.displayName
            }
            if let count = controls.openaiImageGeneration?.count, count > 1 {
                return "x\(count)"
            }
            return isImageGenerationConfigured ? "On" : nil
        }

        if controls.imageGeneration?.responseMode == .imageOnly {
            return "IMG"
        }
        if let ratio = controls.imageGeneration?.aspectRatio?.rawValue {
            return ratio
        }
        if controls.imageGeneration?.seed != nil {
            return "Seed"
        }
        return isImageGenerationConfigured ? "On" : nil
    }

    static func imageGenerationHelpText(
        supportsImageGenerationControl: Bool,
        providerType: ProviderType?,
        controls: GenerationControls,
        isImageGenerationConfigured: Bool
    ) -> String {
        guard supportsImageGenerationControl else { return "Image Generation: Not supported" }

        if providerType == .xai {
            if let ratio = controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio {
                return "Image Generation: \(ratio.displayName)"
            }
            if let count = controls.xaiImageGeneration?.count {
                return "Image Generation: Count \(count)"
            }
            return isImageGenerationConfigured ? "Image Generation: Customized" : "Image Generation: Default"
        }

        if providerType == .openai || providerType == .openaiWebSocket {
            if let size = controls.openaiImageGeneration?.size {
                return "Image Generation: \(size.displayName)"
            }
            if let quality = controls.openaiImageGeneration?.quality {
                return "Image Generation: \(quality.displayName)"
            }
            return isImageGenerationConfigured ? "Image Generation: Customized" : "Image Generation: Default"
        }

        if let ratio = controls.imageGeneration?.aspectRatio?.rawValue {
            return "Image Generation: \(ratio)"
        }
        if controls.imageGeneration?.responseMode == .imageOnly {
            return "Image Generation: Image only"
        }
        return isImageGenerationConfigured ? "Image Generation: Customized" : "Image Generation: Default"
    }

    static func isVideoGenerationConfigured(providerType: ProviderType?, controls: GenerationControls) -> Bool {
        switch providerType {
        case .gemini, .vertexai:
            return !(controls.googleVideoGeneration?.isEmpty ?? true)
        case .xai:
            return !(controls.xaiVideoGeneration?.isEmpty ?? true)
        default:
            return false
        }
    }

    static func videoGenerationBadgeText(
        supportsVideoGenerationControl: Bool,
        providerType: ProviderType?,
        controls: GenerationControls,
        isVideoGenerationConfigured: Bool
    ) -> String? {
        guard supportsVideoGenerationControl else { return nil }

        switch providerType {
        case .gemini, .vertexai:
            let gc = controls.googleVideoGeneration
            if let duration = gc?.durationSeconds { return "\(duration)s" }
            if let ratio = gc?.aspectRatio { return ratio.displayName }
            if let resolution = gc?.resolution { return resolution.displayName }
            return isVideoGenerationConfigured ? "On" : nil
        case .xai:
            if let duration = controls.xaiVideoGeneration?.duration { return "\(duration)s" }
            if let ratio = controls.xaiVideoGeneration?.aspectRatio { return ratio.displayName }
            if let resolution = controls.xaiVideoGeneration?.resolution { return resolution.displayName }
            return isVideoGenerationConfigured ? "On" : nil
        default:
            return nil
        }
    }

    static func videoGenerationHelpText(
        supportsVideoGenerationControl: Bool,
        providerType: ProviderType?,
        controls: GenerationControls,
        isVideoGenerationConfigured: Bool
    ) -> String {
        guard supportsVideoGenerationControl else { return "Video Generation: Not supported" }

        switch providerType {
        case .gemini, .vertexai:
            let gc = controls.googleVideoGeneration
            var parts: [String] = []
            if let duration = gc?.durationSeconds { parts.append("\(duration)s") }
            if let ratio = gc?.aspectRatio { parts.append(ratio.displayName) }
            if let resolution = gc?.resolution { parts.append(resolution.displayName) }
            if let audio = gc?.generateAudio, audio { parts.append("Audio") }
            if parts.isEmpty {
                return isVideoGenerationConfigured ? "Video Generation: Customized" : "Video Generation: Default"
            }
            return "Video Generation: \(parts.joined(separator: ", "))"
        case .xai:
            var parts: [String] = []
            if let duration = controls.xaiVideoGeneration?.duration { parts.append("\(duration)s") }
            if let ratio = controls.xaiVideoGeneration?.aspectRatio { parts.append(ratio.displayName) }
            if let resolution = controls.xaiVideoGeneration?.resolution { parts.append(resolution.displayName) }
            if parts.isEmpty {
                return isVideoGenerationConfigured ? "Video Generation: Customized" : "Video Generation: Default"
            }
            return "Video Generation: \(parts.joined(separator: ", "))"
        default:
            return "Video Generation: Not supported"
        }
    }

    static func defaultPDFProcessingFallbackMode(
        mistralOCRPluginEnabled: Bool,
        mistralOCRConfigured: Bool,
        deepSeekOCRPluginEnabled: Bool,
        deepSeekOCRConfigured: Bool
    ) -> PDFProcessingMode {
        if mistralOCRPluginEnabled, mistralOCRConfigured {
            return .mistralOCR
        }
        if deepSeekOCRPluginEnabled, deepSeekOCRConfigured {
            return .deepSeekOCR
        }
        return .macOSExtract
    }

    static func isPDFProcessingModeAvailable(
        _ mode: PDFProcessingMode,
        supportsNativePDF: Bool,
        mistralOCRPluginEnabled: Bool,
        deepSeekOCRPluginEnabled: Bool
    ) -> Bool {
        switch mode {
        case .native:
            return supportsNativePDF
        case .macOSExtract:
            return true
        case .mistralOCR:
            return mistralOCRPluginEnabled
        case .deepSeekOCR:
            return deepSeekOCRPluginEnabled
        }
    }

    static func resolvedPDFProcessingMode(
        controls: GenerationControls,
        supportsNativePDF: Bool,
        defaultPDFProcessingFallbackMode: PDFProcessingMode,
        mistralOCRPluginEnabled: Bool,
        deepSeekOCRPluginEnabled: Bool
    ) -> PDFProcessingMode {
        let requested = controls.pdfProcessingMode ?? .native
        if isPDFProcessingModeAvailable(
            requested,
            supportsNativePDF: supportsNativePDF,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            deepSeekOCRPluginEnabled: deepSeekOCRPluginEnabled
        ) {
            return requested
        }
        if supportsNativePDF {
            return .native
        }
        return defaultPDFProcessingFallbackMode
    }
}
