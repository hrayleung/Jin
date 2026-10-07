import Foundation

extension ChatModelCapabilitySupport {
    static func supportsCurrentModelImageSizeControl(lowerModelID: String) -> Bool {
        lowerModelID == "gemini-3-pro-image-preview"
            || lowerModelID == "gemini-3.1-flash-image-preview"
            || lowerModelID == "gemini-nano-banana-2.1"
    }

    static func supportedCurrentModelImageAspectRatios(lowerModelID: String) -> [ImageAspectRatio] {
        if lowerModelID == "openai/gpt-5.4-image-2" {
            return []
        }
        if lowerModelID == "gemini-3.1-flash-image-preview"
            || lowerModelID == "gemini-nano-banana-2.1" {
            return ImageAspectRatio.nanoBanana2SupportedCases
        }
        return ImageAspectRatio.defaultSupportedCases
    }

    static func supportedCurrentModelImageSizes(lowerModelID: String) -> [ImageOutputSize] {
        if lowerModelID == "gemini-3.1-flash-image-preview" {
            return ImageOutputSize.nanoBanana2SupportedCases
        }
        // gemini-nano-banana-2.1 falls through to the default set — its documented
        // sizes are 1K/2K/4K and 512px is not offered.
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

    static func isVideoGenerationConfigured(providerType: ProviderType?, controls: GenerationControls) -> Bool {
        switch providerType {
        case .gemini, .vertexai:
            return !(controls.googleVideoGeneration?.isEmpty ?? true)
        case .xai:
            return !(controls.xaiVideoGeneration?.isEmpty ?? true)
        case .openrouter:
            return !(controls.openRouterVideoGeneration?.isEmpty ?? true)
        case .together:
            return !(controls.togetherVideoGeneration?.isEmpty ?? true)
        default:
            return false
        }
    }
}
