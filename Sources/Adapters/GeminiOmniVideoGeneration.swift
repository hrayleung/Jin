import Foundation

/// Gemini Omni Flash video generation via the Interactions API.
///
/// Official: `POST /v1beta/interactions` with `model=gemini-omni-1.1-flash`.
/// Not Veo `:predictLongRunning`. Sampling, negative prompts, and system
/// instructions are rejected (ai.google.dev/gemini-api/docs/omni, 2026-08-28).
enum GeminiOmniVideoRequestSupport {
    static func makeBody(
        modelID: String,
        prompt: String,
        images: [(mimeType: String, base64: String)],
        videos: [(mimeType: String, base64: String)],
        controls: GoogleVideoGenerationControls?
    ) -> [String: Any] {
        var input: [Any] = []
        for image in images {
            input.append([
                "type": "image",
                "data": image.base64,
                "mime_type": image.mimeType
            ])
        }
        for video in videos {
            input.append([
                "type": "video",
                "mime_type": video.mimeType,
                "data": video.base64
            ])
        }
        input.append([
            "type": "text",
            "text": prompt
        ])

        var responseFormat: [String: Any] = ["type": "video"]
        if let aspectRatio = controls?.aspectRatio {
            responseFormat["aspect_ratio"] = aspectRatio.rawValue
        }
        if let resolution = controls?.resolution {
            responseFormat["resolution"] = resolution.rawValue
        }
        if GoogleVideoGenerationCore.omniUsesURIDelivery(resolution: controls?.resolution) {
            responseFormat["delivery"] = "uri"
        }

        return [
            "model": modelID,
            "input": input,
            "response_format": responseFormat,
            "background": false,
            "store": false,
            "stream": false
        ]
    }

    static func videoPayload(from interaction: [String: Any]) -> (mimeType: String, data: Data?, uri: String?)? {
        if let payload = videoPayload(fromContentItems: interaction["output_video"]) {
            return payload
        }

        guard let steps = interaction["steps"] as? [[String: Any]] else { return nil }
        for step in steps.reversed() {
            guard (step["type"] as? String) == "model_output" else { continue }
            if let payload = videoPayload(fromContentItems: step["content"]) {
                return payload
            }
        }
        return nil
    }

    static func fileID(fromURI uri: String) -> String? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = trimmed.range(of: "/files/", options: .caseInsensitive) {
            var remainder = String(trimmed[range.upperBound...])
            if let query = remainder.firstIndex(of: "?") {
                remainder = String(remainder[..<query])
            }
            if let colon = remainder.firstIndex(of: ":") {
                remainder = String(remainder[..<colon])
            }
            remainder = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return remainder.isEmpty ? nil : remainder
        }

        if trimmed.hasPrefix("files/") {
            let remainder = String(trimmed.dropFirst("files/".count))
            let id = remainder.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first
                .map(String.init)?
                .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true).first
                .map(String.init)
            return id?.isEmpty == false ? id : nil
        }

        return nil
    }

    private static func videoPayload(fromContentItems value: Any?) -> (mimeType: String, data: Data?, uri: String?)? {
        if let object = value as? [String: Any] {
            return videoPayload(fromItem: object)
        }
        if let items = value as? [[String: Any]] {
            for item in items where (item["type"] as? String) == "video" {
                if let payload = videoPayload(fromItem: item) {
                    return payload
                }
            }
        }
        return nil
    }

    private static func videoPayload(fromItem item: [String: Any]) -> (mimeType: String, data: Data?, uri: String?)? {
        let mimeType = (item["mime_type"] as? String)?.trimmedNonEmpty
            ?? (item["mimeType"] as? String)?.trimmedNonEmpty
            ?? "video/mp4"
        if let dataString = (item["data"] as? String)?.trimmedNonEmpty,
           let data = Data(base64Encoded: dataString),
           !data.isEmpty {
            return (mimeType, data, nil)
        }
        if let uri = (item["uri"] as? String)?.trimmedNonEmpty {
            return (mimeType, nil, uri)
        }
        return nil
    }
}

extension GeminiAdapter {
    func makeOmniFlashVideoGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        guard let prompt = GoogleVideoGenerationCore.extractPrompt(from: messages) else {
            throw LLMError.invalidRequest(message: "Video generation requires a text prompt.")
        }

        let images = try GoogleVideoGenerationCore.extractImageInputs(from: messages).compactMap { image -> (String, String)? in
            guard let base64 = try GoogleVideoGenerationCore.imageToBase64(image) else { return nil }
            return (image.mimeType, base64)
        }
        let videos = try GoogleVideoGenerationCore.extractVideoInputs(from: messages).compactMap { video -> (String, String)? in
            guard let base64 = try GoogleVideoGenerationCore.videoToBase64(video) else { return nil }
            return (video.mimeType, base64)
        }
        let videoControls = GoogleVideoGenerationCore.sanitizedGoogleVideoControls(
            controls.googleVideoGeneration,
            modelID: modelID
        )
        let body = GeminiOmniVideoRequestSupport.makeBody(
            modelID: modelID,
            prompt: prompt,
            images: images,
            videos: videos,
            controls: videoControls
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try NetworkRequestFactory.makeJSONRequest(
                        url: validatedURL("\(baseURL)/interactions"),
                        headers: geminiHeaders(),
                        body: body
                    )
                    let (startData, _) = try await networkManager.sendRequest(request)
                    let interaction = try decodeOmniInteraction(from: startData)
                    continuation.yield(.messageStart(id: (interaction["id"] as? String) ?? UUID().uuidString))

                    let completed = try await waitForOmniInteraction(interaction)
                    let payload = try await resolveOmniVideoPayload(completed)
                    let videoContent = VideoContent(mimeType: payload.mimeType, data: nil, url: payload.localURL)
                    continuation.yield(.contentDelta(.video(videoContent)))
                    continuation.yield(.messageEnd(usage: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func decodeOmniInteraction(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "(non-UTF-8)"
            throw LLMError.decodingError(
                message: "Gemini Omni Flash returned non-JSON: \(String(raw.prefix(500)))"
            )
        }
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Gemini Omni Flash request failed."
            throw LLMError.providerError(code: "video_generation_failed", message: message)
        }
        return json
    }

    private func waitForOmniInteraction(_ initial: [String: Any]) async throws -> [String: Any] {
        var current = initial
        let pollIntervalNanoseconds: UInt64 = 5_000_000_000
        let maxAttempts = 60

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            if omniInteractionIsFailed(current) {
                let message = (current["error"] as? [String: Any])?["message"] as? String
                    ?? "Gemini Omni Flash video generation failed."
                throw LLMError.providerError(code: "video_generation_failed", message: message)
            }
            if omniInteractionIsComplete(current) {
                return current
            }

            guard attempt + 1 < maxAttempts else { break }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)

            guard let id = (current["id"] as? String)?.trimmedNonEmpty else {
                throw LLMError.decodingError(message: "Gemini Omni Flash did not return an interaction id.")
            }
            let pollRequest = NetworkRequestFactory.makeRequest(
                url: try validatedURL("\(baseURL)/interactions/\(id)"),
                headers: geminiHeaders()
            )
            let (pollData, _) = try await networkManager.sendRequest(pollRequest)
            current = try decodeOmniInteraction(from: pollData)
        }

        throw LLMError.providerError(
            code: "video_generation_timeout",
            message: "Gemini Omni Flash timed out waiting for the generated video."
        )
    }

    private func omniInteractionIsComplete(_ interaction: [String: Any]) -> Bool {
        let status = (interaction["status"] as? String)?.lowercased()
        if status == "completed" || status == "complete" {
            return true
        }
        return GeminiOmniVideoRequestSupport.videoPayload(from: interaction) != nil
    }

    private func omniInteractionIsFailed(_ interaction: [String: Any]) -> Bool {
        let status = (interaction["status"] as? String)?.lowercased()
        return status == "failed" || status == "cancelled" || status == "canceled"
    }

    private func resolveOmniVideoPayload(
        _ interaction: [String: Any]
    ) async throws -> (mimeType: String, localURL: URL) {
        guard let payload = GeminiOmniVideoRequestSupport.videoPayload(from: interaction) else {
            let raw = (try? JSONSerialization.data(withJSONObject: interaction))
                .flatMap { String(data: $0, encoding: .utf8) }
                ?? "(unserializable)"
            throw LLMError.decodingError(
                message: "Gemini Omni Flash completed but no video was returned. Response: \(String(raw.prefix(500)))"
            )
        }

        if let data = payload.data, !data.isEmpty {
            let localURL = try VideoAttachmentUtility.saveDataToLocal(data, mimeType: payload.mimeType)
            return (payload.mimeType, localURL)
        }

        guard let uri = payload.uri else {
            throw LLMError.decodingError(message: "Gemini Omni Flash video had neither data nor a URI.")
        }
        return try await downloadOmniVideo(uri: uri, mimeType: payload.mimeType)
    }

    private func downloadOmniVideo(uri: String, mimeType: String) async throws -> (mimeType: String, localURL: URL) {
        if let fileID = GeminiOmniVideoRequestSupport.fileID(fromURI: uri) {
            try await waitForOmniFileActive(fileID: fileID)
            let downloadURL = try validatedURL("\(baseURL)/files/\(fileID):download?alt=media")
            let (localURL, downloadedMIME) = try await VideoAttachmentUtility.downloadToLocal(
                from: downloadURL,
                networkManager: networkManager,
                authHeader: (key: "x-goog-api-key", value: apiKey)
            )
            return (downloadedMIME.isEmpty ? mimeType : downloadedMIME, localURL)
        }

        guard let url = URL(string: uri) else {
            throw LLMError.decodingError(message: "Invalid Gemini Omni Flash video URI: \(uri)")
        }
        let (localURL, downloadedMIME) = try await VideoAttachmentUtility.downloadToLocal(
            from: url,
            networkManager: networkManager,
            authHeader: (key: "x-goog-api-key", value: apiKey)
        )
        return (downloadedMIME.isEmpty ? mimeType : downloadedMIME, localURL)
    }

    private func waitForOmniFileActive(fileID: String) async throws {
        let pollIntervalNanoseconds: UInt64 = 5_000_000_000
        let maxAttempts = 36

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            let request = NetworkRequestFactory.makeRequest(
                url: try validatedURL("\(baseURL)/files/\(fileID)"),
                headers: geminiHeaders()
            )
            let (data, _) = try await networkManager.sendRequest(request)
            let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let state = (json["state"] as? String)?.uppercased()
                ?? (json["status"] as? String)?.uppercased()
            if state == "ACTIVE" || state == "SUCCEEDED" {
                return
            }
            if state == "FAILED" {
                let message = (json["error"] as? [String: Any])?["message"] as? String
                    ?? "Gemini Omni Flash file processing failed."
                throw LLMError.providerError(code: "video_generation_failed", message: message)
            }
            if attempt + 1 < maxAttempts {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }

        throw LLMError.providerError(
            code: "video_generation_timeout",
            message: "Gemini Omni Flash timed out waiting for the video file to become ACTIVE."
        )
    }
}
