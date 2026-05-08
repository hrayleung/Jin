import Foundation

enum XAIModelSupport {
    static let imageGenerationModelIDs: Set<String> = [
        "grok-imagine-image",
        "grok-imagine-image-quality",
        "grok-imagine-image-pro",
        "grok-2-image-1212",
    ]

    static let resolutionCapableImageModelIDs: Set<String> = [
        "grok-imagine-image-quality",
        "grok-imagine-image-pro",
    ]
    static let videoGenerationModelIDs: Set<String> = [
        "grok-imagine-video",
    ]

    private static let chatReasoningModelIDs: Set<String> = [
        "grok-4",
        "grok-4.3",
        "grok-4.20",
        "grok-4.20-multi-agent",
        "grok-4.20-multi-agent-0309",
        "grok-4-1",
        "grok-4-1-fast",
        "grok-4-1-fast-non-reasoning",
        "grok-4-1-fast-reasoning",
        "grok-4-1212",
    ]

    static func modelInfo(from model: XAIModelData) -> ModelInfo {
        ModelInfo(
            id: model.id,
            name: model.id,
            capabilities: inferredCapabilities(for: model),
            contextWindow: model.contextWindow ?? 128_000,
            reasoningConfig: nil
        )
    }

    static func inferredCapabilities(for model: XAIModelData) -> ModelCapability {
        let lowerID = model.id.lowercased()

        let inputModalities = Set((model.inputModalities ?? []).map { $0.lowercased() })
        let outputModalities = Set((model.outputModalities ?? []).map { $0.lowercased() })
        let allModalities = Set((model.modalities ?? []).map { $0.lowercased() })

        let hasVideoOutput = outputModalities.contains(where: { $0.contains("video") })
            || allModalities.contains(where: { $0.contains("video") })
        if hasVideoOutput || isVideoGenerationModelID(lowerID) {
            return [.videoGeneration]
        }

        let hasImageOutput = outputModalities.contains(where: { $0.contains("image") })
            || allModalities.contains(where: { $0.contains("image") })
        if hasImageOutput || isImageGenerationModelID(lowerID) {
            return [.imageGeneration]
        }

        var caps: ModelCapability = [.streaming, .toolCalling, .promptCaching]

        if inputModalities.contains(where: { $0.contains("image") })
            || outputModalities.contains(where: { $0.contains("image") }) {
            caps.insert(.vision)
        }

        if chatReasoningModelIDs.contains(lowerID) {
            caps.insert(.vision)
            caps.insert(.reasoning)
        }

        if supportsNativePDF(model.id) {
            caps.insert(.nativePDF)
        }

        return caps
    }

    static func isImageGenerationModelID(_ modelID: String) -> Bool {
        imageGenerationModelIDs.contains(modelID.lowercased())
    }

    static func isVideoGenerationModelID(_ modelID: String) -> Bool {
        videoGenerationModelIDs.contains(modelID.lowercased())
    }

    static func supportsImageResolutionControl(_ modelID: String) -> Bool {
        resolutionCapableImageModelIDs.contains(modelID.lowercased())
    }

    static func supportsNativePDF(_ modelID: String) -> Bool {
        JinModelSupport.supportsNativePDF(providerType: .xai, modelID: modelID)
    }
}
