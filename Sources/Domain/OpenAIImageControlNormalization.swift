import Foundation

extension OpenAIImageModelSupport {
    static func normalize(_ controls: inout OpenAIImageGenerationControls, for modelID: String) {
        guard let profile = OpenAIImageModelSupport.profile(for: modelID) else {
            controls.size = nil
            controls.quality = nil
            controls.style = nil
            controls.background = nil
            controls.outputFormat = nil
            controls.outputCompression = nil
            controls.moderation = nil
            controls.inputFidelity = nil
            controls.complexity = nil
            controls.frameCount = nil
            controls.frameDurationMilliseconds = nil
            controls.inputMode = nil
            controls.editGuidance = nil
            return
        }

        if let size = controls.size,
           OpenAIImageModelSupport.validate(size: size, for: modelID, outputFormat: controls.outputFormat) != nil {
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

        if let format = controls.outputFormat, !profile.outputFormats.contains(format) {
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

        if controls.outputFormat?.supportsCompression != true {
            controls.outputCompression = nil
        }

        if !profile.supportsComplexity {
            controls.complexity = nil
            controls.inputMode = nil
            controls.editGuidance = nil
        }
        if controls.outputFormat == .svg {
            controls.count = 1
        }
        if controls.outputFormat == .gif {
            if let count = controls.frameCount { controls.frameCount = min(max(count, 2), 64) }
            if let duration = controls.frameDurationMilliseconds {
                let bounded = min(max(duration, 20), 2_000)
                controls.frameDurationMilliseconds = ((bounded + 5) / 10) * 10
            }
        } else {
            controls.frameCount = nil
            controls.frameDurationMilliseconds = nil
        }
        if controls.outputFormat?.isGenerationOnly == true, controls.background == .transparent {
            controls.background = nil
        }
    }
}
