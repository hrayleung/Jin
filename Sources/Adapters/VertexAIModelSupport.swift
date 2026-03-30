import Foundation

struct VertexAIModelSupport {
    private enum ModelClassification {
        case knownGemini(isImageGeneration: Bool)
        case knownImagen
        case unknownImagen
        case unknown
    }

    let knownModels: [(id: String, name: String, contextWindow: Int)] = [
        ("gemini-3-pro-preview", "Gemini 3 Pro Preview", 1_048_576),
        ("gemini-3.1-pro-preview", "Gemini 3.1 Pro Preview", 1_048_576),
        ("gemini-3-flash-preview", "Gemini 3 Flash Preview", 1_048_576),
        ("gemini-3-pro-image-preview", "Gemini 3 Pro Image Preview", 65_536),
        ("gemini-3.1-flash-image-preview", "Gemini 3.1 Flash Image Preview", 131_072),
        ("gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash-Lite Preview", 1_048_576),
        ("gemini-2.5-pro", "Gemini 2.5 Pro", 1_048_576),
        ("gemini-2.5-flash", "Gemini 2.5 Flash", 1_048_576),
        ("gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite", 1_048_576),
        ("gemini-2.5-flash-image", "Gemini 2.5 Flash Image", 32_768),
        ("gemini-2.0-flash", "Gemini 2.0 Flash", 1_048_576),
        ("gemini-2.0-flash-lite", "Gemini 2.0 Flash Lite", 1_048_576),
        ("gemini-1.5-pro", "Gemini 1.5 Pro", 2_097_152),
        ("gemini-1.5-flash", "Gemini 1.5 Flash", 1_048_576),
        ("imagen-4.0-generate-preview-06-06", "Imagen 4.0", 0),
        ("imagen-3.0-generate-002", "Imagen 3.0", 0),
    ]

    private let knownImagenModelIDs: Set<String> = [
        "imagen-4.0-generate-preview-06-06",
        "imagen-3.0-generate-002"
    ]

    private var knownGeminiModelIDs: Set<String> {
        GeminiModelConstants.knownModelIDs
    }

    private var exactImageGenerationModelIDs: Set<String> {
        GeminiModelConstants.imageGenerationModelIDs
    }

    func supportsImageGeneration(_ modelID: String) -> Bool {
        switch classify(modelID) {
        case .knownGemini(let isImageGeneration):
            return isImageGeneration
        case .knownImagen:
            return true
        case .unknownImagen, .unknown:
            return false
        }
    }

    func supportsFunctionCalling(_ modelID: String) -> Bool {
        switch classify(modelID) {
        case .knownGemini(let isImageGeneration):
            return !isImageGeneration
        case .knownImagen, .unknownImagen, .unknown:
            return false
        }
    }

    func supportsWebSearch(providerConfig: ProviderConfig, modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    func supportsCodeExecution(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: .vertexai, modelID: modelID)
    }

    func supportsGoogleMaps(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsGoogleMaps(for: .vertexai, modelID: modelID)
    }

    func supportsImageSize(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower == "gemini-3-pro-image-preview" || lower == "gemini-3.1-flash-image-preview"
    }

    func supportsImageSize(_ modelID: String, imageSize: ImageOutputSize) -> Bool {
        guard supportsImageSize(modelID) else { return false }
        if modelID.lowercased() == "gemini-3-pro-image-preview" {
            return imageSize != .size512px
        }
        return true
    }

    func requestTimeoutInterval(for modelID: String, controls: GenerationControls) -> TimeInterval? {
        guard supportsImageGeneration(modelID) else {
            return nil
        }

        switch controls.imageGeneration?.imageSize {
        case .size512px:
            return VertexImageRequestTimeout.size1KSeconds
        case .size4K:
            return VertexImageRequestTimeout.size4KSeconds
        case .size2K:
            return VertexImageRequestTimeout.size2KSeconds
        case .size1K:
            return VertexImageRequestTimeout.size1KSeconds
        case .none:
            return VertexImageRequestTimeout.defaultSeconds
        }
    }

    func supportsThinking(_ modelID: String) -> Bool {
        switch classify(modelID) {
        case .knownGemini:
            return modelID.lowercased() != "gemini-2.5-flash-image"
        case .knownImagen, .unknownImagen, .unknown:
            return false
        }
    }

    func supportsThinkingConfig(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return supportsThinking(modelID)
            && lower != "gemini-3-pro-image-preview"
            && lower != "gemini-3.1-flash-image-preview"
    }

    func supportsThinkingLevel(_ modelID: String) -> Bool {
        supportsThinkingConfig(modelID)
    }

    func supportsNativePDF(_ modelID: String) -> Bool {
        GeminiModelConstants.supportsVertexNativePDF(modelID)
    }

    func mapEffortToVertexLevel(_ effort: ReasoningEffort, modelID: String) -> String {
        GeminiModelConstants.mapEffortToThinkingLevel(effort, for: .vertexai, modelID: modelID)
    }

    func makeModelInfo(id: String, displayName: String, contextWindow: Int) -> ModelInfo {
        switch classify(id) {
        case .knownImagen:
            return makeKnownImagenModelInfo(id: id, displayName: displayName, contextWindow: contextWindow)
        case .unknownImagen, .unknown:
            return makeConservativeModelInfo(id: id, displayName: displayName, contextWindow: contextWindow)
        case .knownGemini(let imageModel):
            var capabilities: ModelCapability = []
            if !imageModel {
                capabilities.formUnion([.streaming, .toolCalling, .promptCaching])
            }
            capabilities.insert(.vision)
            if !imageModel {
                capabilities.insert(.audio)
            }

            let reasoningConfig = buildReasoningConfig(modelID: id, geminiModel: true, capabilities: &capabilities)

            if supportsNativePDF(id) {
                capabilities.insert(.nativePDF)
            }
            if supportsCodeExecution(id) {
                capabilities.insert(.codeExecution)
            }
            if imageModel {
                capabilities.insert(.imageGeneration)
            }
            if GoogleVideoGenerationCore.isVideoGenerationModel(id) {
                capabilities.insert(.videoGeneration)
            }

            return ModelInfo(
                id: id,
                name: displayName,
                capabilities: capabilities,
                contextWindow: contextWindow,
                reasoningConfig: reasoningConfig,
                isEnabled: true
            )
        }
    }

    private func makeKnownImagenModelInfo(id: String, displayName: String, contextWindow: Int) -> ModelInfo {
        ModelInfo(
            id: id,
            name: displayName,
            capabilities: [.imageGeneration],
            contextWindow: contextWindow,
            reasoningConfig: nil,
            isEnabled: true
        )
    }

    private func makeConservativeModelInfo(id: String, displayName: String, contextWindow: Int) -> ModelInfo {
        ModelInfo(
            id: id,
            name: displayName,
            capabilities: [],
            contextWindow: contextWindow,
            reasoningConfig: nil,
            isEnabled: true
        )
    }

    private func buildReasoningConfig(
        modelID: String,
        geminiModel: Bool,
        capabilities: inout ModelCapability
    ) -> ModelReasoningConfig? {
        let lower = modelID.lowercased()
        guard supportsThinking(modelID), geminiModel else { return nil }

        capabilities.insert(.reasoning)

        if GeminiModelConstants.gemini25TextModelIDs.contains(lower) {
            return ModelReasoningConfig(type: .budget, defaultBudget: 2048)
        }
        if lower == "gemini-3.1-flash-lite-preview" {
            return ModelReasoningConfig(type: .effort, defaultEffort: .minimal)
        }
        if supportsThinkingConfig(modelID) {
            return ModelReasoningConfig(type: .effort, defaultEffort: .medium)
        }
        return nil
    }

    private func classify(_ modelID: String) -> ModelClassification {
        let lower = modelID.lowercased()
        if knownImagenModelIDs.contains(lower) {
            return .knownImagen
        }
        if knownGeminiModelIDs.contains(lower) {
            return .knownGemini(isImageGeneration: exactImageGenerationModelIDs.contains(lower))
        }
        if lower.hasPrefix("imagen-") {
            return .unknownImagen
        }
        return .unknown
    }
}

private enum VertexImageRequestTimeout {
    static let defaultSeconds: TimeInterval = 600
    static let size1KSeconds: TimeInterval = 360
    static let size2KSeconds: TimeInterval = 720
    static let size4KSeconds: TimeInterval = 1_200
}
