import Foundation

extension OpenRouterAdapter {
    func buildVideoGenerationRequest(
        modelID: String,
        prompt: String,
        images: [ImageContent],
        controls: GenerationControls
    ) throws -> URLRequest {
        let videoControls = sanitizedVideoControls(controls.openRouterVideoGeneration, for: modelID)

        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
        ]

        if let duration = videoControls?.durationSeconds {
            body["duration"] = duration
        }
        if let aspectRatio = videoControls?.aspectRatio {
            body["aspect_ratio"] = aspectRatio.rawValue
        }
        if let resolution = videoControls?.resolution {
            body["resolution"] = resolution.rawValue
        }
        if let generateAudio = videoControls?.generateAudio {
            body["generate_audio"] = generateAudio
        }
        if let seed = videoControls?.seed {
            body["seed"] = seed
        }

        deepMergeDictionary(
            into: &body,
            additional: try imagePayload(
                from: images,
                mode: videoControls?.imageInputMode ?? .smart
            )
        )

        let passthrough = passthroughParameters(for: modelID, controls: controls)
        if !passthrough.isEmpty,
           let providerSlug = OpenRouterVideoModelSupport.providerPassthroughSlug(for: modelID) {
            body["provider"] = [
                "options": [
                    providerSlug: [
                        "parameters": passthrough
                    ]
                ]
            ]
        }

        for (key, value) in controls.providerSpecific {
            guard !Self.videoProviderPassthroughKeys.contains(key) else { continue }
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/videos"),
            apiKey: apiKey,
            body: body,
            additionalHeaders: openRouterHeaders,
            includeUserAgent: false
        )
    }

    func passthroughParameters(for modelID: String, controls: GenerationControls) -> [String: Any] {
        var passthrough: [String: Any] = [:]

        if let watermark = controls.openRouterVideoGeneration?.watermark,
           OpenRouterVideoModelSupport.supportsWatermark(for: modelID) {
            passthrough["watermark"] = watermark
        }

        for key in Self.videoProviderPassthroughKeys {
            if let value = controls.providerSpecific[key]?.value {
                passthrough[key] = value
            }
        }

        return passthrough
    }

    func imagePayload(
        from images: [ImageContent],
        mode: OpenRouterVideoImageInputMode
    ) throws -> [String: Any] {
        let imageURLs = try images.compactMap { try imageToURLString($0) }
        guard !imageURLs.isEmpty else { return [:] }

        switch mode {
        case .smart:
            if imageURLs.count == 1 {
                return [
                    "frame_images": [
                        frameImagePayload(url: imageURLs[0], frameType: "first_frame")
                    ]
                ]
            }
            if imageURLs.count == 2 {
                return [
                    "frame_images": [
                        frameImagePayload(url: imageURLs[0], frameType: "first_frame"),
                        frameImagePayload(url: imageURLs[1], frameType: "last_frame"),
                    ]
                ]
            }
            return [
                "input_references": imageURLs.map { referenceImagePayload(url: $0) }
            ]
        case .frameImages:
            var frames: [[String: Any]] = []
            if let first = imageURLs.first {
                frames.append(frameImagePayload(url: first, frameType: "first_frame"))
            }
            if imageURLs.count > 1 {
                frames.append(frameImagePayload(url: imageURLs[1], frameType: "last_frame"))
            }
            return frames.isEmpty ? [:] : ["frame_images": frames]
        case .referenceImages:
            return [
                "input_references": imageURLs.map { referenceImagePayload(url: $0) }
            ]
        }
    }

    func sanitizedVideoControls(
        _ controls: OpenRouterVideoGenerationControls?,
        for modelID: String
    ) -> OpenRouterVideoGenerationControls? {
        guard var controls else { return nil }

        if let duration = controls.durationSeconds,
           !OpenRouterVideoModelSupport.supportedDurations(for: modelID).contains(duration) {
            controls.durationSeconds = nil
        }

        if let aspectRatio = controls.aspectRatio,
           !OpenRouterVideoModelSupport.supportedAspectRatios(for: modelID).contains(aspectRatio) {
            controls.aspectRatio = nil
        }

        if let resolution = controls.resolution,
           !OpenRouterVideoModelSupport.supportedResolutions(for: modelID).contains(resolution) {
            controls.resolution = nil
        }

        if OpenRouterVideoModelSupport.supportsAudio(for: modelID) == false {
            controls.generateAudio = nil
        }

        if OpenRouterVideoModelSupport.supportsWatermark(for: modelID) == false {
            controls.watermark = nil
        }

        return controls.isEmpty ? nil : controls
    }

    func frameImagePayload(url: String, frameType: String) -> [String: Any] {
        var payload = imageURLPayload(url: url)
        payload["frame_type"] = frameType
        return payload
    }

    func referenceImagePayload(url: String) -> [String: Any] {
        [
            "type": "image_url",
            "image_url": [
                "url": url
            ],
        ]
    }

    func imageURLPayload(url: String) -> [String: Any] {
        [
            "type": "image_url",
            "image_url": [
                "url": url
            ]
        ]
    }

    static let videoProviderPassthroughKeys: Set<String> = [
        "req_key",
        "watermark",
    ]
}
