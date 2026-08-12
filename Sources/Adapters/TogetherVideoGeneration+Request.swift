import Foundation

extension TogetherAdapter {
    /// Together video jobs live under `/v2/videos`, while chat uses `/v1`.
    /// Preserve custom hosts/proxies instead of hardcoding Together's default origin.
    var videoBaseURL: String {
        let chat = baseURL
        if let range = chat.range(of: "/v1", options: [.backwards, .caseInsensitive]),
           range.upperBound == chat.endIndex {
            return chat.replacingCharacters(in: range, with: "/v2")
        }
        if chat.lowercased().hasSuffix("/v2") {
            return chat
        }
        return "\(chat)/v2"
    }

    func buildVideoGenerationRequest(
        modelID: String,
        prompt: String,
        images: [ImageContent],
        controls: GenerationControls
    ) throws -> URLRequest {
        let videoControls = sanitizedVideoControls(controls.togetherVideoGeneration, for: modelID)

        // Seedance / Together videos API:
        // POST https://api.together.xyz/v2/videos
        // seconds is a *string*; ratio/resolution use lowercase tiers.
        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
        ]

        if let duration = videoControls?.durationSeconds {
            body["seconds"] = String(duration)
        }
        if let aspectRatio = videoControls?.aspectRatio {
            body["ratio"] = aspectRatio.rawValue
        }
        if let resolution = videoControls?.resolution {
            body["resolution"] = resolution.rawValue
        }
        if let seed = videoControls?.seed {
            body["seed"] = seed
        }

        // Seedance uses settings.audio (not top-level generate_audio) per
        // docs.together.ai/docs/seedance2.0-quickstart.
        if TogetherVideoModelSupport.supportsAudio(for: modelID),
           let generateAudio = videoControls?.generateAudio {
            body["settings"] = ["audio": generateAudio]
        }

        deepMergeDictionary(
            into: &body,
            additional: try mediaPayload(
                from: images,
                mode: videoControls?.imageInputMode ?? .smart
            )
        )

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(videoBaseURL)/videos"),
            apiKey: apiKey,
            body: body,
            includeUserAgent: false
        )
    }

    func mediaPayload(
        from images: [ImageContent],
        mode: TogetherVideoImageInputMode
    ) throws -> [String: Any] {
        let imageURLs = try images.compactMap { try imageToURLString($0) }
        guard !imageURLs.isEmpty else { return [:] }

        switch mode {
        case .smart:
            if imageURLs.count == 1 {
                return [
                    "media": [
                        "frame_images": [
                            frameImagePayload(url: imageURLs[0], frame: "first")
                        ]
                    ]
                ]
            }
            if imageURLs.count == 2 {
                return [
                    "media": [
                        "frame_images": [
                            frameImagePayload(url: imageURLs[0], frame: "first"),
                            frameImagePayload(url: imageURLs[1], frame: "last"),
                        ]
                    ]
                ]
            }
            return [
                "media": [
                    "reference_images": imageURLs
                ]
            ]
        case .frameImages:
            var frames: [[String: Any]] = []
            if let first = imageURLs.first {
                frames.append(frameImagePayload(url: first, frame: "first"))
            }
            if imageURLs.count > 1 {
                frames.append(frameImagePayload(url: imageURLs[1], frame: "last"))
            }
            return frames.isEmpty ? [:] : ["media": ["frame_images": frames]]
        case .referenceImages:
            return [
                "media": [
                    "reference_images": imageURLs
                ]
            ]
        }
    }

    func frameImagePayload(url: String, frame: String) -> [String: Any] {
        [
            "input_image": url,
            "frame": frame,
        ]
    }

    func sanitizedVideoControls(
        _ controls: TogetherVideoGenerationControls?,
        for modelID: String
    ) -> TogetherVideoGenerationControls? {
        guard var controls else { return nil }

        if let duration = controls.durationSeconds,
           !TogetherVideoModelSupport.supportedDurations(for: modelID).contains(duration) {
            controls.durationSeconds = nil
        }

        if let aspectRatio = controls.aspectRatio,
           !TogetherVideoModelSupport.supportedAspectRatios(for: modelID).contains(aspectRatio) {
            controls.aspectRatio = nil
        }

        if let resolution = controls.resolution,
           !TogetherVideoModelSupport.supportedResolutions(for: modelID).contains(resolution) {
            controls.resolution = nil
        }

        if TogetherVideoModelSupport.supportsAudio(for: modelID) == false {
            controls.generateAudio = nil
        }

        return controls.isEmpty ? nil : controls
    }
}
