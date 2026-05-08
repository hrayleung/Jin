import Foundation

enum XAIMediaRequestSupport {
    struct RequestComponents {
        var endpoint: String
        var body: [String: Any]
    }

    static func imageRequestComponents(
        modelID: String,
        prompt: String,
        imageURL: String?,
        controls: XAIImageGenerationControls?
    ) -> RequestComponents {
        let isImageEdit = imageURL?.isEmpty == false
        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt
        ]

        if let count = controls?.count, count > 0 {
            body["n"] = min(max(count, 1), 10)
        }
        if let imageURL, !imageURL.isEmpty {
            body["image"] = ["url": imageURL]
        }

        if !isImageEdit,
           let aspectRatio = controls?.aspectRatio ?? controls?.size?.mappedAspectRatio {
            body["aspect_ratio"] = aspectRatio.rawValue
        }

        if !isImageEdit,
           XAIModelSupport.supportsImageResolutionControl(modelID),
           let resolution = controls?.resolution {
            body["resolution"] = resolution.rawValue
        }

        body["response_format"] = "b64_json"
        if let user = normalizedTrimmedString(controls?.user) {
            body["user"] = user
        }

        return RequestComponents(
            endpoint: isImageEdit ? "images/edits" : "images/generations",
            body: body
        )
    }

    static func videoRequestComponents(
        modelID: String,
        prompt: String,
        imageURL: String?,
        videoURL: String?,
        controls: XAIVideoGenerationControls?
    ) -> RequestComponents {
        let isVideoEdit = videoURL?.isEmpty == false
        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt
        ]

        if !isVideoEdit {
            if let duration = controls?.duration {
                body["duration"] = min(max(duration, 1), 15)
            }
            if let aspectRatio = controls?.aspectRatio, supportedVideoAspectRatios.contains(aspectRatio) {
                body["aspect_ratio"] = aspectRatio.rawValue
            }
            if let resolution = controls?.resolution {
                body["resolution"] = resolution.rawValue
            }
        }

        if let videoURL, !videoURL.isEmpty {
            body["video"] = ["url": videoURL]
        } else if let imageURL, !imageURL.isEmpty {
            body["image"] = ["url": imageURL]
        }

        return RequestComponents(
            endpoint: isVideoEdit ? "videos/edits" : "videos/generations",
            body: body
        )
    }

    static let supportedVideoAspectRatios: Set<XAIAspectRatio> = [
        .ratio1x1,
        .ratio16x9,
        .ratio9x16,
        .ratio4x3,
        .ratio3x4,
        .ratio3x2,
        .ratio2x3
    ]
}
