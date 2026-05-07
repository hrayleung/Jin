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
                if controls.xaiVideoGeneration?.isEmpty == true {
                    controls.xaiVideoGeneration = nil
                }
                controls.googleVideoGeneration = nil
                controls.openRouterVideoGeneration = nil
            case .gemini, .vertexai:
                if controls.googleVideoGeneration?.isEmpty == true {
                    controls.googleVideoGeneration = nil
                }
                controls.xaiVideoGeneration = nil
                controls.openRouterVideoGeneration = nil
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
            default:
                controls.xaiVideoGeneration = nil
                controls.googleVideoGeneration = nil
                controls.openRouterVideoGeneration = nil
            }
        } else {
            controls.xaiVideoGeneration = nil
            controls.googleVideoGeneration = nil
            controls.openRouterVideoGeneration = nil
        }
    }
}
