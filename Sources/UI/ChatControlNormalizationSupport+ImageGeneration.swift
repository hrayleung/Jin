import Foundation

extension ChatControlNormalizationSupport {
    static func normalizeImageGenerationControls(
        controls: inout GenerationControls,
        supportsImageGenerationControl: Bool,
        providerType: ProviderType?,
        supportsCurrentModelImageSizeControl: Bool,
        supportedCurrentModelImageSizes: [ImageOutputSize],
        supportedCurrentModelImageAspectRatios: [ImageAspectRatio],
        lowerModelID: String
    ) {
        if supportsImageGenerationControl {
            if providerType == .openai || providerType == .openaiWebSocket {
                controls.imageGeneration = nil
                controls.xaiImageGeneration = nil
                if var openaiImage = controls.openaiImageGeneration {
                    normalizeOpenAIImageControls(&openaiImage, lowerModelID: lowerModelID)
                    controls.openaiImageGeneration = openaiImage.isEmpty ? nil : openaiImage
                }
            } else if providerType == .xai {
                controls.imageGeneration = nil
                controls.openaiImageGeneration = nil
                if var xaiImage = controls.xaiImageGeneration {
                    xaiImage.quality = nil
                    xaiImage.style = nil
                    if xaiImage.aspectRatio != nil {
                        xaiImage.size = nil
                    }
                    if !XAIModelSupport.supportsImageResolutionControl(lowerModelID) {
                        xaiImage.resolution = nil
                    }
                    controls.xaiImageGeneration = xaiImage.isEmpty ? nil : xaiImage
                }
            } else {
                if !supportsCurrentModelImageSizeControl {
                    controls.imageGeneration?.imageSize = nil
                } else if let size = controls.imageGeneration?.imageSize,
                          !supportedCurrentModelImageSizes.contains(size) {
                    controls.imageGeneration?.imageSize = nil
                }
                if let ratio = controls.imageGeneration?.aspectRatio,
                   !supportedCurrentModelImageAspectRatios.contains(ratio) {
                    controls.imageGeneration?.aspectRatio = nil
                }
                if providerType != .vertexai {
                    controls.imageGeneration?.vertexPersonGeneration = nil
                    controls.imageGeneration?.vertexOutputMIMEType = nil
                    controls.imageGeneration?.vertexCompressionQuality = nil
                }
                if controls.imageGeneration?.isEmpty == true {
                    controls.imageGeneration = nil
                }
                controls.xaiImageGeneration = nil
                controls.openaiImageGeneration = nil
            }
        } else {
            controls.imageGeneration = nil
            controls.xaiImageGeneration = nil
            controls.openaiImageGeneration = nil
        }
    }

    static func normalizeOpenAIImageControls(
        _ controls: inout OpenAIImageGenerationControls,
        lowerModelID: String
    ) {
        guard let profile = OpenAIImageModelSupport.profile(for: lowerModelID) else {
            controls.size = nil
            controls.quality = nil
            controls.style = nil
            controls.background = nil
            controls.outputFormat = nil
            controls.outputCompression = nil
            controls.moderation = nil
            controls.inputFidelity = nil
            return
        }

        if let size = controls.size,
           OpenAIImageModelSupport.validate(size: size, for: lowerModelID) != nil {
            controls.size = nil
        }

        if let quality = controls.quality,
           !profile.qualityOptions.contains(quality) {
            controls.quality = nil
        }

        if !profile.supportsStyle {
            controls.style = nil
        }

        if let background = controls.background,
           !profile.backgroundOptions.contains(background) {
            controls.background = nil
        }

        if !profile.supportsOutputFormat {
            controls.outputFormat = nil
        }

        if !profile.supportsOutputCompression {
            controls.outputCompression = nil
        }

        if !profile.supportsModeration {
            controls.moderation = nil
        }

        if !profile.supportsInputFidelity {
            controls.inputFidelity = nil
        }

        if controls.background == .transparent,
           controls.outputFormat == .jpeg {
            controls.outputFormat = .png
        }

        if controls.outputFormat == nil || controls.outputFormat == .png {
            controls.outputCompression = nil
        }
    }
}
