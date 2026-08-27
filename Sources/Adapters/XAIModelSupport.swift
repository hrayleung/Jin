import Foundation

enum XAIModelSupport {
    static let imageGenerationModelIDs: Set<String> = [
        "grok-imagine-image-2.0",
        "grok-imagine-image",
        "grok-imagine-image-quality",
        "grok-imagine-image-pro",
        "grok-2-image-1212",
    ]

    static let resolutionCapableImageModelIDs: Set<String> = [
        "grok-imagine-image-2.0",
        "grok-imagine-image-quality",
        "grok-imagine-image-pro",
    ]

    /// `quality` is documented only for `grok-imagine-image-2.0` (`low`/`medium`).
    static let qualityCapableImageModelIDs: Set<String> = [
        "grok-imagine-image-2.0",
    ]

    static let image2QualityOptions: [XAIImageQuality] = [.low, .medium]
    static let videoGenerationModelIDs: Set<String> = [
        "grok-imagine-video",
        "grok-imagine-video-1.5",
        "grok-imagine-video-1.5-preview",
        "grok-imagine-video-1.5-2026-05-30",
    ]

    /// Video-generation models that reject pure text-to-video and require an
    /// input image (image-to-video). Verified against the live xAI API, which
    /// returns `400 {"error":"Text-to-video is not supported for this model."}`
    /// for these IDs. The base `grok-imagine-video` does support text-to-video.
    static let imageRequiredVideoGenerationModelIDs: Set<String> = [
        "grok-imagine-video-1.5",
        "grok-imagine-video-1.5-preview",
        "grok-imagine-video-1.5-2026-05-30",
    ]

    /// 1080p is only supported on `grok-imagine-video-1.5` for image-to-video
    /// (docs.x.ai video generation).
    static let fullHDVideoGenerationModelIDs: Set<String> = [
        "grok-imagine-video-1.5",
        "grok-imagine-video-1.5-preview",
        "grok-imagine-video-1.5-2026-05-30",
    ]

    private static let chatReasoningModelIDs: Set<String> = [
        "grok-4",
        "grok-4.3",
        "grok-4.5",
        "grok-4.6",
        "grok-4.20",
        "grok-4.20-multi-agent",
        "grok-4.20-multi-agent-0309",
        "grok-4.20-0309-reasoning",
        "grok-build-0.1",
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

    /// Whether the model rejects text-only prompts and needs an image (or video) input.
    static func requiresImageInputForVideoGeneration(_ modelID: String) -> Bool {
        imageRequiredVideoGenerationModelIDs.contains(modelID.lowercased())
    }

    static func supportsImageResolutionControl(_ modelID: String) -> Bool {
        resolutionCapableImageModelIDs.contains(modelID.lowercased())
    }

    static func supportsImageQualityControl(_ modelID: String) -> Bool {
        qualityCapableImageModelIDs.contains(modelID.lowercased())
    }

    static func supportedImageQualities(for modelID: String) -> [XAIImageQuality] {
        supportsImageQualityControl(modelID) ? image2QualityOptions : []
    }

    static func supportsFullHDVideoResolution(_ modelID: String) -> Bool {
        fullHDVideoGenerationModelIDs.contains(modelID.lowercased())
    }

    static func availableVideoResolutions(for modelID: String) -> [XAIVideoResolution] {
        if supportsFullHDVideoResolution(modelID) {
            return [.res480p, .res720p, .res1080p]
        }
        return [.res480p, .res720p]
    }

    /// Base Imagine Video supports text/image/video inputs. The 1.5 family is
    /// image→video only (docs.x.ai model pages).
    static func supportsTextToVideo(_ modelID: String) -> Bool {
        !requiresImageInputForVideoGeneration(modelID)
    }

    static func supportsReferenceToVideo(_ modelID: String) -> Bool {
        // Documented on grok-imagine-video; 1.5 is first-frame image→video only.
        !requiresImageInputForVideoGeneration(modelID)
    }

    static func supportsVideoEdit(_ modelID: String) -> Bool {
        !requiresImageInputForVideoGeneration(modelID)
    }

    static func supportsVideoExtension(_ modelID: String) -> Bool {
        !requiresImageInputForVideoGeneration(modelID)
    }

    /// Modes exposed in the composer menu for a given model ID.
    static func availableVideoModes(for modelID: String) -> [XAIVideoMode] {
        var modes: [XAIVideoMode] = [.auto]
        if supportsTextToVideo(modelID) {
            modes.append(.textToVideo)
        }
        modes.append(.imageToVideo)
        if supportsReferenceToVideo(modelID) {
            modes.append(.referenceToVideo)
        }
        if supportsVideoEdit(modelID) {
            modes.append(.editVideo)
        }
        if supportsVideoExtension(modelID) {
            modes.append(.extendVideo)
        }
        return modes
    }

    static func supportsNativePDF(_ modelID: String) -> Bool {
        JinModelSupport.supportsNativePDF(providerType: .xai, modelID: modelID)
    }
}
