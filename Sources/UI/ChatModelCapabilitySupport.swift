import Foundation

enum ChatModelCapabilitySupport {
    static func resolvedClaudeManagedAgentModelInfo(
        threadModelID: String,
        providerEntity: ProviderConfigEntity?,
        threadControls: GenerationControls?
    ) -> ModelInfo? {
        var controls = threadControls ?? GenerationControls()
        providerEntity?.applyClaudeManagedDefaults(into: &controls)

        let remoteModelID = ClaudeManagedAgentRuntime.resolvedRuntimeModelID(
            threadModelID: threadModelID,
            controls: controls
        )

        if let remoteModel = ModelCatalog.seededModels(for: .anthropic).first(where: { $0.id == remoteModelID }) {
            return ModelInfo(
                id: remoteModelID,
                name: controls.claudeManagedAgentModelDisplayName
                    ?? controls.claudeManagedAgentDisplayName
                    ?? remoteModel.name,
                capabilities: remoteModel.capabilities,
                contextWindow: remoteModel.contextWindow,
                maxOutputTokens: remoteModel.maxOutputTokens,
                reasoningConfig: remoteModel.reasoningConfig,
                overrides: remoteModel.overrides,
                catalogMetadata: remoteModel.catalogMetadata,
                isEnabled: true
            )
        }

        return providerEntity?.selectableModels.first(where: { $0.id == threadModelID })
    }

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
        case "qwen3p6-plus":
            caps.insert(.vision)
            caps.remove(.audio)
            caps.remove(.reasoning)
            contextWindow = 128_000
            reasoningConfig = nil
            if name == model.id { name = "Qwen3.6 Plus" }
        case "deepseek-v3p2":
            caps.remove(.audio)
            caps.remove(.vision)
            caps.remove(.reasoning)
            contextWindow = 163_800
            reasoningConfig = nil
            if name == model.id { name = "DeepSeek V3.2" }
        case "kimi-k2-instruct-0905":
            caps.remove(.audio)
            caps.remove(.vision)
            caps.remove(.reasoning)
            contextWindow = 262_100
            reasoningConfig = nil
            if name == model.id { name = "Kimi K2 Instruct 0905" }
        case "kimi-k2p5":
            caps.insert(.vision)
            caps.insert(.reasoning)
            contextWindow = 262_100
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "Kimi K2.5" }
        case "qwen3-235b-a22b":
            caps.remove(.audio)
            caps.remove(.vision)
            caps.remove(.reasoning)
            contextWindow = 131_100
            reasoningConfig = nil
            if name == model.id { name = "Qwen3 235B A22B" }
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
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .anthropic, .claudeManagedAgents, .perplexity,
             .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .none:
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
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo:
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
        case .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .xai, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan,
             .cerebras, .sambanova, .codexAppServer, .morphllm, .opencodeGo, .none:
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
        mineruOCRPluginEnabled: Bool,
        mineruOCRConfigured: Bool,
        deepSeekOCRPluginEnabled: Bool,
        deepSeekOCRConfigured: Bool
    ) -> PDFProcessingMode {
        if mistralOCRPluginEnabled, mistralOCRConfigured {
            return .mistralOCR
        }
        if mineruOCRPluginEnabled, mineruOCRConfigured {
            return .mineruOCR
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
        mineruOCRPluginEnabled: Bool,
        deepSeekOCRPluginEnabled: Bool
    ) -> Bool {
        switch mode {
        case .native:
            return supportsNativePDF
        case .macOSExtract:
            return true
        case .mistralOCR:
            return mistralOCRPluginEnabled
        case .mineruOCR:
            return mineruOCRPluginEnabled
        case .deepSeekOCR:
            return deepSeekOCRPluginEnabled
        }
    }

    static func resolvedPDFProcessingMode(
        controls: GenerationControls,
        supportsNativePDF: Bool,
        defaultPDFProcessingFallbackMode: PDFProcessingMode,
        mistralOCRPluginEnabled: Bool,
        mineruOCRPluginEnabled: Bool,
        deepSeekOCRPluginEnabled: Bool
    ) -> PDFProcessingMode {
        let requested = controls.pdfProcessingMode ?? .native
        if isPDFProcessingModeAvailable(
            requested,
            supportsNativePDF: supportsNativePDF,
            mistralOCRPluginEnabled: mistralOCRPluginEnabled,
            mineruOCRPluginEnabled: mineruOCRPluginEnabled,
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
