import Foundation

extension ChatControlNormalizationSupport {
    static func normalizeVideoGenerationControls(
        controls: inout GenerationControls,
        supportsVideoGenerationControl: Bool,
        providerType: ProviderType?,
        lowerModelID: String
    ) {
        if supportsVideoGenerationControl {
            switch providerType {
            case .xai:
                if let mode = controls.xaiVideoGeneration?.mode {
                    let available = XAIModelSupport.availableVideoModes(for: lowerModelID)
                    if !available.contains(mode) {
                        controls.xaiVideoGeneration?.mode = nil
                    }
                }
                if let resolution = controls.xaiVideoGeneration?.resolution,
                   !XAIModelSupport.availableVideoResolutions(for: lowerModelID).contains(resolution) {
                    controls.xaiVideoGeneration?.resolution = nil
                }
                // Edit inherits shape; extend only accepts duration of the extension.
                let mode = controls.xaiVideoGeneration?.resolvedMode ?? .auto
                switch mode {
                case .editVideo:
                    controls.xaiVideoGeneration?.duration = nil
                    controls.xaiVideoGeneration?.aspectRatio = nil
                    controls.xaiVideoGeneration?.resolution = nil
                case .extendVideo:
                    controls.xaiVideoGeneration?.aspectRatio = nil
                    controls.xaiVideoGeneration?.resolution = nil
                    if let duration = controls.xaiVideoGeneration?.duration {
                        let range = XAIMediaRequestSupport.extendVideoDurationRange
                        controls.xaiVideoGeneration?.duration = min(max(duration, range.lowerBound), range.upperBound)
                    }
                case .referenceToVideo:
                    if let duration = controls.xaiVideoGeneration?.duration {
                        let range = XAIMediaRequestSupport.referenceToVideoDurationRange
                        controls.xaiVideoGeneration?.duration = min(max(duration, range.lowerBound), range.upperBound)
                    }
                default:
                    break
                }
                if controls.xaiVideoGeneration?.isEmpty == true {
                    controls.xaiVideoGeneration = nil
                }
                controls.googleVideoGeneration = nil
                controls.openRouterVideoGeneration = nil
                controls.togetherVideoGeneration = nil
            case .gemini, .vertexai:
                controls.googleVideoGeneration = GoogleVideoGenerationCore.sanitizedGoogleVideoControls(
                    controls.googleVideoGeneration,
                    modelID: lowerModelID
                )
                controls.xaiVideoGeneration = nil
                controls.openRouterVideoGeneration = nil
                controls.togetherVideoGeneration = nil
            case .openrouter:
                if let duration = controls.openRouterVideoGeneration?.durationSeconds,
                   !OpenRouterVideoModelSupport.supportedDurations(for: lowerModelID).contains(duration) {
                    controls.openRouterVideoGeneration?.durationSeconds = nil
                }
                if let aspectRatio = controls.openRouterVideoGeneration?.aspectRatio,
                   !OpenRouterVideoModelSupport.supportedAspectRatios(for: lowerModelID).contains(aspectRatio) {
                    controls.openRouterVideoGeneration?.aspectRatio = nil
                }
                if let resolution = controls.openRouterVideoGeneration?.resolution,
                   !OpenRouterVideoModelSupport.supportedResolutions(for: lowerModelID).contains(resolution) {
                    controls.openRouterVideoGeneration?.resolution = nil
                }
                if OpenRouterVideoModelSupport.supportsAudio(for: lowerModelID) == false {
                    controls.openRouterVideoGeneration?.generateAudio = nil
                }
                if OpenRouterVideoModelSupport.supportsWatermark(for: lowerModelID) == false {
                    controls.openRouterVideoGeneration?.watermark = nil
                }
                if controls.openRouterVideoGeneration?.isEmpty == true {
                    controls.openRouterVideoGeneration = nil
                }
                controls.xaiVideoGeneration = nil
                controls.googleVideoGeneration = nil
                controls.togetherVideoGeneration = nil
            case .together:
                if let duration = controls.togetherVideoGeneration?.durationSeconds,
                   !TogetherVideoModelSupport.supportedDurations(for: lowerModelID).contains(duration) {
                    controls.togetherVideoGeneration?.durationSeconds = nil
                }
                if let aspectRatio = controls.togetherVideoGeneration?.aspectRatio,
                   !TogetherVideoModelSupport.supportedAspectRatios(for: lowerModelID).contains(aspectRatio) {
                    controls.togetherVideoGeneration?.aspectRatio = nil
                }
                if let resolution = controls.togetherVideoGeneration?.resolution,
                   !TogetherVideoModelSupport.supportedResolutions(for: lowerModelID).contains(resolution) {
                    controls.togetherVideoGeneration?.resolution = nil
                }
                if TogetherVideoModelSupport.supportsAudio(for: lowerModelID) == false {
                    controls.togetherVideoGeneration?.generateAudio = nil
                }
                if controls.togetherVideoGeneration?.isEmpty == true {
                    controls.togetherVideoGeneration = nil
                }
                controls.xaiVideoGeneration = nil
                controls.googleVideoGeneration = nil
                controls.openRouterVideoGeneration = nil
            default:
                controls.xaiVideoGeneration = nil
                controls.googleVideoGeneration = nil
                controls.openRouterVideoGeneration = nil
                controls.togetherVideoGeneration = nil
            }
        } else {
            controls.xaiVideoGeneration = nil
            controls.googleVideoGeneration = nil
            controls.openRouterVideoGeneration = nil
            controls.togetherVideoGeneration = nil
        }
    }
}
