import Foundation

extension ChatModelCapabilitySupport {
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

    static func videoGenerationBadgeText(
        supportsVideoGenerationControl: Bool,
        providerType: ProviderType?,
        controls: GenerationControls,
        isVideoGenerationConfigured: Bool
    ) -> String? {
        guard supportsVideoGenerationControl else { return nil }

        switch providerType {
        case .gemini, .vertexai:
            return isVideoGenerationConfigured ? "On" : nil
        case .xai:
            return isVideoGenerationConfigured ? "On" : nil
        case .openrouter:
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
        case .openrouter:
            var parts: [String] = []
            if let duration = controls.openRouterVideoGeneration?.durationSeconds { parts.append("\(duration)s") }
            if let ratio = controls.openRouterVideoGeneration?.aspectRatio { parts.append(ratio.displayName) }
            if let resolution = controls.openRouterVideoGeneration?.resolution { parts.append(resolution.displayName) }
            if let mode = controls.openRouterVideoGeneration?.imageInputMode { parts.append(mode.displayName) }
            if controls.openRouterVideoGeneration?.generateAudio == true { parts.append("Audio") }
            if controls.openRouterVideoGeneration?.watermark == true { parts.append("Watermark") }
            if parts.isEmpty {
                return isVideoGenerationConfigured ? "Video Generation: Customized" : "Video Generation: Default"
            }
            return "Video Generation: \(parts.joined(separator: ", "))"
        default:
            return "Video Generation: Not supported"
        }
    }
}
