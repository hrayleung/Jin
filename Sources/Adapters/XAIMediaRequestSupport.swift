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

        if !isImageEdit,
           XAIModelSupport.supportsImageQualityControl(modelID),
           let quality = controls?.quality,
           XAIModelSupport.supportedImageQualities(for: modelID).contains(quality) {
            body["quality"] = quality.rawValue
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

    /// Builds the video request for the resolved workflow.
    ///
    /// Docs (docs.x.ai/developers/model-capabilities/video/*):
    /// - text / image / reference → `videos/generations`
    /// - edit → `videos/edits` (inherits duration/aspect/resolution from input video)
    /// - extend → `videos/extensions` (`duration` = extension length only)
    /// - `image` and `reference_images` are mutually exclusive
    static func videoRequestComponents(
        modelID: String,
        prompt: String,
        imageURL: String?,
        referenceImageURLs: [String]?,
        videoURL: String?,
        mode: XAIVideoRequestMode,
        controls: XAIVideoGenerationControls?
    ) -> RequestComponents {
        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt
        ]

        switch mode {
        case .textToVideo:
            applyGenerationShapeControls(
                to: &body,
                modelID: modelID,
                imageURL: nil,
                durationRange: generationDurationRange,
                controls: controls
            )

        case .imageToVideo:
            if let imageURL, !imageURL.isEmpty {
                body["image"] = ["url": imageURL]
            }
            applyGenerationShapeControls(
                to: &body,
                modelID: modelID,
                imageURL: imageURL,
                durationRange: generationDurationRange,
                controls: controls
            )

        case .referenceToVideo:
            let refs = (referenceImageURLs ?? []).filter { !$0.isEmpty }
            if !refs.isEmpty {
                body["reference_images"] = refs.map { ["url": $0] }
            }
            // Reference-to-video is capped at 10s (docs.x.ai / provider integrations).
            applyGenerationShapeControls(
                to: &body,
                modelID: modelID,
                imageURL: nil,
                durationRange: referenceToVideoDurationRange,
                controls: controls
            )

        case .editVideo:
            // Edit inherits duration / aspect / resolution from the source video.
            if let videoURL, !videoURL.isEmpty {
                body["video"] = ["url": videoURL]
            }

        case .extendVideo:
            // Duration is the length of the *extended portion* only (docs: 2–10s, default 6).
            if let videoURL, !videoURL.isEmpty {
                body["video"] = ["url": videoURL]
            }
            if let duration = controls?.duration {
                body["duration"] = clampDuration(duration, to: extendVideoDurationRange)
            }
        }

        return RequestComponents(
            endpoint: endpoint(for: mode),
            body: body
        )
    }

    /// Backward-compatible helper used by older call sites/tests (edit vs generation only).
    static func videoRequestComponents(
        modelID: String,
        prompt: String,
        imageURL: String?,
        videoURL: String?,
        controls: XAIVideoGenerationControls?
    ) -> RequestComponents {
        let mode: XAIVideoRequestMode
        if videoURL?.isEmpty == false {
            mode = (controls?.mode == .extendVideo) ? .extendVideo : .editVideo
        } else if imageURL?.isEmpty == false {
            mode = .imageToVideo
        } else {
            mode = .textToVideo
        }
        return videoRequestComponents(
            modelID: modelID,
            prompt: prompt,
            imageURL: imageURL,
            referenceImageURLs: nil,
            videoURL: videoURL,
            mode: mode,
            controls: controls
        )
    }

    static func endpoint(for mode: XAIVideoRequestMode) -> String {
        switch mode {
        case .textToVideo, .imageToVideo, .referenceToVideo:
            return "videos/generations"
        case .editVideo:
            return "videos/edits"
        case .extendVideo:
            return "videos/extensions"
        }
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

    /// Text / image-to-video: 1–15s (docs.x.ai video generation).
    static let generationDurationRange: ClosedRange<Int> = 1...15
    /// Reference-to-video: max 10s (provider integrations + docs examples).
    static let referenceToVideoDurationRange: ClosedRange<Int> = 1...10
    /// Extend-video: extension segment only, 2–10s (docs.x.ai video extension).
    static let extendVideoDurationRange: ClosedRange<Int> = 2...10

    static func durationOptions(for mode: XAIVideoMode) -> [Int] {
        switch mode {
        case .extendVideo:
            return [2, 3, 5, 6, 8, 10]
        case .referenceToVideo:
            return [3, 5, 8, 10]
        case .auto, .textToVideo, .imageToVideo:
            return [3, 5, 8, 10, 15]
        case .editVideo:
            return []
        }
    }

    // MARK: - Private

    private static func applyGenerationShapeControls(
        to body: inout [String: Any],
        modelID: String,
        imageURL: String?,
        durationRange: ClosedRange<Int>,
        controls: XAIVideoGenerationControls?
    ) {
        if let duration = controls?.duration {
            body["duration"] = clampDuration(duration, to: durationRange)
        }
        if let aspectRatio = controls?.aspectRatio, supportedVideoAspectRatios.contains(aspectRatio) {
            body["aspect_ratio"] = aspectRatio.rawValue
        }
        if let resolution = controls?.resolution {
            // 1080p is only valid for grok-imagine-video-1.5 image-to-video.
            if resolution == .res1080p {
                let hasImage = imageURL?.isEmpty == false
                if XAIModelSupport.supportsFullHDVideoResolution(modelID), hasImage {
                    body["resolution"] = resolution.rawValue
                }
            } else {
                body["resolution"] = resolution.rawValue
            }
        }
    }

    private static func clampDuration(_ duration: Int, to range: ClosedRange<Int>) -> Int {
        min(max(duration, range.lowerBound), range.upperBound)
    }
}
