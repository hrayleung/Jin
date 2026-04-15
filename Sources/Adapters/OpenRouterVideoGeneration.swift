import Foundation

extension OpenRouterAdapter {

    func makeVideoGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let prompt = try videoGenerationPrompt(from: messages)
        let images = videoGenerationImages(from: messages)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildVideoGenerationRequest(
                        modelID: modelID,
                        prompt: prompt,
                        images: images,
                        controls: controls
                    )
                    let (startData, _) = try await networkManager.sendRequest(request)
                    let startJSON = try decodeJSONObject(startData)

                    if let failure = failureMessage(from: startJSON) {
                        throw LLMError.providerError(code: "video_generation_failed", message: failure)
                    }

                    guard let jobID = extractVideoJobID(from: startJSON) else {
                        let raw = String(data: startData, encoding: .utf8) ?? "(non-UTF-8)"
                        throw LLMError.decodingError(
                            message: "OpenRouter video generation did not return a job ID. Response: \(String(raw.prefix(500)))"
                        )
                    }

                    continuation.yield(.messageStart(id: jobID))

                    try await pollVideoUntilDone(
                        jobID: jobID,
                        initialPollURLString: stringValue(startJSON["polling_url"]),
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func buildVideoGenerationRequest(
        modelID: String,
        prompt: String,
        images: [ImageContent],
        controls: GenerationControls
    ) throws -> URLRequest {
        let videoControls = controls.openRouterVideoGeneration

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

    private func pollVideoUntilDone(
        jobID: String,
        initialPollURLString: String?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let pollIntervalNanoseconds: UInt64 = 10_000_000_000
        let maxAttempts = 60
        let pollURL = try resolvedPollingURL(jobID: jobID, pollURLString: initialPollURLString)

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }

            let request = makeGETRequest(
                url: pollURL,
                apiKey: apiKey,
                additionalHeaders: openRouterHeaders,
                includeUserAgent: false
            )

            let (pollData, pollResponse) = try await networkManager.sendRawRequest(request)
            let pollJSON = try decodeJSONObject(pollData)

            if let failure = failureMessage(from: pollJSON) {
                throw LLMError.providerError(code: "video_generation_failed", message: failure)
            }

            switch classifyVideoStatus(json: pollJSON, httpStatus: pollResponse.statusCode) {
            case .pending:
                continue
            case .completed:
                let downloadURL = try resolvedDownloadURL(jobID: jobID, responseJSON: pollJSON)
                let (localURL, mimeType) = try await VideoAttachmentUtility.downloadToLocal(
                    from: downloadURL,
                    networkManager: networkManager,
                    authHeader: (key: "Authorization", value: "Bearer \(apiKey)")
                )
                continuation.yield(.contentDelta(.video(VideoContent(mimeType: mimeType, data: nil, url: localURL))))
                continuation.yield(.messageEnd(usage: nil))
                continuation.finish()
                return
            case .failed(let message):
                throw LLMError.providerError(
                    code: "video_generation_failed",
                    message: message ?? "Video generation failed on the server."
                )
            }
        }

        throw LLMError.providerError(
            code: "video_generation_timeout",
            message: "OpenRouter video generation timed out after polling for ~10 minutes."
        )
    }

    private func resolvedPollingURL(jobID: String, pollURLString: String?) throws -> URL {
        if let pollURLString,
           let pollURL = URL(string: pollURLString),
           let scheme = pollURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            return pollURL
        }

        return try validatedURL("\(baseURL)/videos/\(jobID)")
    }

    private func resolvedDownloadURL(jobID: String, responseJSON: [String: Any]) throws -> URL {
        if let unsignedURLs = responseJSON["unsigned_urls"] as? [String],
           let first = unsignedURLs.first,
           let url = URL(string: first),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            return url
        }

        return try validatedURL("\(baseURL)/videos/\(jobID)/content?index=0")
    }

    private func passthroughParameters(for modelID: String, controls: GenerationControls) -> [String: Any] {
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

    private func imagePayload(
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

    private func frameImagePayload(url: String, frameType: String) -> [String: Any] {
        [
            "type": "input_image",
            "image_url": url,
            "frame_type": frameType,
        ]
    }

    private func referenceImagePayload(url: String) -> [String: Any] {
        [
            "type": "input_image",
            "image_url": url,
        ]
    }

    private func videoGenerationPrompt(from messages: [Message]) throws -> String {
        for message in messages.reversed() where message.role == .user {
            let text = message.content.compactMap { part -> String? in
                guard case .text(let value) = part else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                return text
            }
        }

        throw LLMError.invalidRequest(message: "OpenRouter video generation requires a text prompt.")
    }

    private func videoGenerationImages(from messages: [Message]) -> [ImageContent] {
        if let latestUserImages = latestUserImageInputs(from: messages), !latestUserImages.isEmpty {
            return latestUserImages
        }

        for message in messages.reversed() where message.role == .assistant || message.role == .user {
            let images = imageInputs(in: message)
            if !images.isEmpty {
                return images
            }
        }

        return []
    }

    private func latestUserImageInputs(from messages: [Message]) -> [ImageContent]? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        let images = imageInputs(in: latestUserMessage)
        return images.isEmpty ? nil : images
    }

    private func imageInputs(in message: Message) -> [ImageContent] {
        message.content.compactMap { part in
            guard case .image(let image) = part else { return nil }
            return image
        }
    }

    private func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError(message: "OpenRouter video generation returned non-JSON response.")
        }
        return json
    }

    private func extractVideoJobID(from json: [String: Any]) -> String? {
        stringValue(json["id"])
            ?? stringValue(json["generation_id"])
            ?? stringValue(json["video_id"])
            ?? stringValue(json["request_id"])
    }

    private func classifyVideoStatus(json: [String: Any], httpStatus: Int) -> OpenRouterVideoPollStatus {
        let status = stringValue(json["status"])?.lowercased()

        switch status {
        case "pending", "queued", "processing", "in_progress":
            return .pending
        case "completed", "complete", "done", "success":
            return .completed
        case "failed", "error", "cancelled", "canceled", "expired":
            return .failed(failureMessage(from: json))
        default:
            break
        }

        if responseHasVideoOutput(json) {
            return .completed
        }

        if httpStatus >= 400 {
            return .failed(failureMessage(from: json) ?? "HTTP \(httpStatus)")
        }

        return .pending
    }

    private func responseHasVideoOutput(_ json: [String: Any]) -> Bool {
        if let unsignedURLs = json["unsigned_urls"] as? [String], !unsignedURLs.isEmpty {
            return true
        }
        if let output = json["output"] as? [[String: Any]], !output.isEmpty {
            return true
        }
        return false
    }

    private func failureMessage(from json: [String: Any]) -> String? {
        if let direct = stringValue(json["message"]) {
            return direct
        }
        if let error = stringValue(json["error"]) {
            return error
        }
        if let errorObject = json["error"] as? [String: Any] {
            return stringValue(errorObject["message"])
                ?? stringValue(errorObject["detail"])
                ?? stringValue(errorObject["reason"])
        }
        if let data = json["data"] as? [String: Any] {
            return failureMessage(from: data)
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let videoProviderPassthroughKeys: Set<String> = [
        "req_key",
        "watermark",
    ]
}

private enum OpenRouterVideoPollStatus {
    case pending
    case completed
    case failed(String?)
}
