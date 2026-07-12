import Foundation

/// Resolves the effective xAI video request mode from user controls + attachments.
///
/// Official workflows (docs.x.ai):
/// - text-to-video / image-to-video / reference-to-video → `/videos/generations`
/// - edit-video → `/videos/edits`
/// - extend-video → `/videos/extensions`
enum XAIVideoModeResolution {
    struct Resolved {
        var mode: XAIVideoRequestMode
        var imageURL: String?
        var referenceImageURLs: [String]
        var videoURL: String?
        var promptMode: XAIMediaPromptSupport.EditMode
    }

    static func resolve(
        modelID: String,
        controls: XAIVideoGenerationControls?,
        imageURLs: [String],
        videoURL: String?
    ) throws -> Resolved {
        let preferred = controls?.resolvedMode ?? .auto
        let hasVideo = videoURL?.isEmpty == false
        let images = imageURLs.filter { !$0.isEmpty }
        let hasImages = !images.isEmpty

        switch preferred {
        case .textToVideo:
            try requireTextToVideo(modelID: modelID)
            return Resolved(
                mode: .textToVideo,
                imageURL: nil,
                referenceImageURLs: [],
                videoURL: nil,
                promptMode: .none
            )

        case .imageToVideo:
            guard let first = images.first else {
                throw LLMError.invalidRequest(
                    message: "Image-to-video needs a starting image. Attach an image and try again."
                )
            }
            return Resolved(
                mode: .imageToVideo,
                imageURL: first,
                referenceImageURLs: [],
                videoURL: nil,
                promptMode: .image
            )

        case .referenceToVideo:
            try requireReferenceToVideo(modelID: modelID)
            guard !images.isEmpty else {
                throw LLMError.invalidRequest(
                    message: "Reference-to-video needs one or more reference images. Attach images and try again."
                )
            }
            return Resolved(
                mode: .referenceToVideo,
                imageURL: nil,
                referenceImageURLs: images,
                videoURL: nil,
                promptMode: .image
            )

        case .editVideo:
            try requireVideoEdit(modelID: modelID)
            guard let videoURL, hasVideo else {
                throw LLMError.invalidRequest(
                    message: "Video edit needs a source video. Attach a video (or paste a public HTTPS video URL) and try again."
                )
            }
            return Resolved(
                mode: .editVideo,
                imageURL: nil,
                referenceImageURLs: [],
                videoURL: videoURL,
                promptMode: .video
            )

        case .extendVideo:
            try requireVideoExtension(modelID: modelID)
            guard let videoURL, hasVideo else {
                throw LLMError.invalidRequest(
                    message: "Video extension needs a source video. Attach a video (or paste a public HTTPS video URL) and try again."
                )
            }
            return Resolved(
                mode: .extendVideo,
                imageURL: nil,
                referenceImageURLs: [],
                videoURL: videoURL,
                promptMode: .video
            )

        case .auto:
            return try resolveAuto(
                modelID: modelID,
                images: images,
                videoURL: hasVideo ? videoURL : nil
            )
        }
    }

    // MARK: - Auto

    private static func resolveAuto(
        modelID: String,
        images: [String],
        videoURL: String?
    ) throws -> Resolved {
        if let videoURL {
            try requireVideoEdit(modelID: modelID)
            return Resolved(
                mode: .editVideo,
                imageURL: nil,
                referenceImageURLs: [],
                videoURL: videoURL,
                promptMode: .video
            )
        }

        if images.count >= 2, XAIModelSupport.supportsReferenceToVideo(modelID) {
            return Resolved(
                mode: .referenceToVideo,
                imageURL: nil,
                referenceImageURLs: images,
                videoURL: nil,
                promptMode: .image
            )
        }

        if let first = images.first {
            return Resolved(
                mode: .imageToVideo,
                imageURL: first,
                referenceImageURLs: [],
                videoURL: nil,
                promptMode: .image
            )
        }

        try requireTextToVideo(modelID: modelID)
        return Resolved(
            mode: .textToVideo,
            imageURL: nil,
            referenceImageURLs: [],
            videoURL: nil,
            promptMode: .none
        )
    }

    // MARK: - Capability gates

    private static func requireTextToVideo(modelID: String) throws {
        guard XAIModelSupport.supportsTextToVideo(modelID) else {
            throw LLMError.invalidRequest(
                message: "This model doesn't support text-to-video. Attach a starting image to generate a video (image-to-video)."
            )
        }
    }

    private static func requireReferenceToVideo(modelID: String) throws {
        guard XAIModelSupport.supportsReferenceToVideo(modelID) else {
            throw LLMError.invalidRequest(
                message: "This model doesn't support reference-to-video. Use grok-imagine-video, or switch to image-to-video with a single starting frame."
            )
        }
    }

    private static func requireVideoEdit(modelID: String) throws {
        guard XAIModelSupport.supportsVideoEdit(modelID) else {
            throw LLMError.invalidRequest(
                message: "This model doesn't support video edit. Use grok-imagine-video for edit workflows."
            )
        }
    }

    private static func requireVideoExtension(modelID: String) throws {
        guard XAIModelSupport.supportsVideoExtension(modelID) else {
            throw LLMError.invalidRequest(
                message: "This model doesn't support video extension. Use grok-imagine-video for extend workflows."
            )
        }
    }
}
