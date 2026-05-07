import Foundation

extension ChatEditorDraftSupport {
    static func prepareImageGenerationEditorDraft(
        current: ImageGenerationControls?,
        supportedAspectRatios: [ImageAspectRatio],
        supportedImageSizes: [ImageOutputSize]
    ) -> PreparedImageGenerationEditorDraft {
        var draft = current ?? ImageGenerationControls()
        if let ratio = draft.aspectRatio, !supportedAspectRatios.contains(ratio) {
            draft.aspectRatio = nil
        }
        if let size = draft.imageSize, !supportedImageSizes.contains(size) {
            draft.imageSize = nil
        }
        return PreparedImageGenerationEditorDraft(
            draft: draft,
            seedDraft: draft.seed.map(String.init) ?? "",
            compressionQualityDraft: draft.vertexCompressionQuality.map(String.init) ?? ""
        )
    }

    static func isImageGenerationDraftValid(
        seedDraft: String,
        compressionQualityDraft: String
    ) -> Bool {
        if let seedText = seedDraft.trimmedNonEmpty, Int(seedText) == nil {
            return false
        }

        if let qualityText = compressionQualityDraft.trimmedNonEmpty {
            guard let quality = Int(qualityText), (0...100).contains(quality) else {
                return false
            }
        }

        return true
    }

    static func applyImageGenerationDraft(
        draft: ImageGenerationControls,
        seedDraft: String,
        compressionQualityDraft: String,
        supportsCurrentModelImageSizeControl: Bool,
        supportedCurrentModelImageSizes: [ImageOutputSize],
        supportedCurrentModelImageAspectRatios: [ImageAspectRatio],
        providerType: ProviderType?
        ) -> Result<ImageGenerationControls?, ChatEditorDraftError> {
        var draft = draft

        if let seedText = seedDraft.trimmedNonEmpty {
            guard let seed = Int(seedText) else {
                return .failure(.message("Seed must be an integer."))
            }
            draft.seed = seed
        } else {
            draft.seed = nil
        }

        if let qualityText = compressionQualityDraft.trimmedNonEmpty {
            guard let quality = Int(qualityText), (0...100).contains(quality) else {
                return .failure(.message("JPEG quality must be an integer between 0 and 100."))
            }
            draft.vertexCompressionQuality = quality
        } else {
            draft.vertexCompressionQuality = nil
        }

        if !supportsCurrentModelImageSizeControl {
            draft.imageSize = nil
        } else if let size = draft.imageSize, !supportedCurrentModelImageSizes.contains(size) {
            draft.imageSize = nil
        }

        if let ratio = draft.aspectRatio, !supportedCurrentModelImageAspectRatios.contains(ratio) {
            draft.aspectRatio = nil
        }

        if providerType != .vertexai {
            draft.vertexPersonGeneration = nil
            draft.vertexOutputMIMEType = nil
            draft.vertexCompressionQuality = nil
        }

        return .success(draft.isEmpty ? nil : draft)
    }
}
