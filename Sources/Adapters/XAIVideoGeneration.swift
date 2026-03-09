import Foundation

extension XAIAdapter {

    // MARK: - Video Generation Stream

    func makeVideoGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let videoInput = videoInputForVideoGeneration(from: messages)
        let imageURL = try imageURLForImageGeneration(from: messages)
        let isVideoToVideo = videoInput != nil
        let isImageToVideo = !isVideoToVideo && imageURL?.isEmpty == false
        let prompt = try mediaPrompt(
            from: messages,
            mode: isVideoToVideo ? .video : (isImageToVideo ? .image : .none)
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let resolvedVideoURL = try await resolvedVideoURL(for: videoInput)

                    let startRequest = try buildVideoGenerationRequest(
                        modelID: modelID,
                        prompt: prompt,
                        imageURL: isImageToVideo ? imageURL : nil,
                        videoURL: isVideoToVideo ? resolvedVideoURL : nil,
                        controls: controls
                    )
                    let (startData, _) = try await networkManager.sendRequest(startRequest)
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let startResponse = try decoder.decode(XAIVideoStartResponse.self, from: startData)

                    if let apiError = startResponse.error {
                        throw LLMError.providerError(
                            code: apiError.code ?? "video_generation_error",
                            message: apiError.message
                        )
                    }

                    guard let requestID = startResponse.resolvedID, !requestID.isEmpty else {
                        let raw = String(data: startData, encoding: .utf8) ?? "(non-UTF-8 data)"
                        throw LLMError.decodingError(
                            message: "xAI video generation did not return a request ID. Response: \(String(raw.prefix(500)))"
                        )
                    }

                    continuation.yield(.messageStart(id: requestID))

                    try await pollVideoUntilDone(
                        requestID: requestID,
                        decoder: decoder,
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

    // MARK: - Video Polling

    private func pollVideoUntilDone(
        requestID: String,
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let pollIntervalNanoseconds: UInt64 = 3_000_000_000
        let maxAttempts = 200
        var firstPollSnapshot: String?
        var lastPollSnapshot: String?
        var consecutiveDecodeFailures = 0
        let maxConsecutiveDecodeFailures = 5

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }

            var pollRequest = URLRequest(url: try validatedURL("\(baseURL)/videos/\(requestID)"))
            pollRequest.httpMethod = "GET"
            pollRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (pollData, pollHTTPResponse) = try await networkManager.sendRawRequest(pollRequest)
            let rawBody = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
            let snapshot = "HTTP \(pollHTTPResponse.statusCode): \(String(rawBody.prefix(800)))"
            lastPollSnapshot = snapshot
            if firstPollSnapshot == nil { firstPollSnapshot = snapshot }

            let statusResponse = try? decoder.decode(XAIVideoStatusResponse.self, from: pollData)

            if let apiError = statusResponse?.error {
                throw LLMError.providerError(
                    code: apiError.code ?? "video_poll_error",
                    message: apiError.message
                )
            }

            let rawJSON = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any]

            let status = resolveVideoStatus(
                codable: statusResponse,
                rawJSON: rawJSON,
                httpStatus: pollHTTPResponse.statusCode
            )

            switch status {
            case .done:
                consecutiveDecodeFailures = 0
                guard let videoURL = extractVideoURL(codable: statusResponse, rawJSON: rawJSON) else {
                    throw LLMError.decodingError(
                        message: "xAI video generation completed but no video URL found. Response: \(String(rawBody.prefix(500)))"
                    )
                }

                let (localURL, mimeType) = try await downloadVideoToLocal(from: videoURL)
                let video = VideoContent(mimeType: mimeType, data: nil, url: localURL)
                continuation.yield(.contentDelta(.video(video)))
                continuation.yield(.messageEnd(usage: nil))
                continuation.finish()
                return

            case .expired:
                throw LLMError.providerError(
                    code: "video_generation_expired",
                    message: "Video generation request expired before completing."
                )

            case .failed(let message):
                throw LLMError.providerError(
                    code: "video_generation_failed",
                    message: message ?? "Video generation failed on the server."
                )

            case .pending:
                consecutiveDecodeFailures = try trackDecodeFailures(
                    statusResponse: statusResponse,
                    rawJSON: rawJSON,
                    httpStatus: pollHTTPResponse.statusCode,
                    rawBody: rawBody,
                    consecutiveFailures: consecutiveDecodeFailures,
                    maxFailures: maxConsecutiveDecodeFailures
                )
                continue
            }
        }

        throw LLMError.providerError(
            code: "video_generation_timeout",
            message: "Video generation timed out after polling for ~10 minutes.\n\nFirst poll: \(firstPollSnapshot ?? "nil")\n\nLast poll: \(lastPollSnapshot ?? "nil")"
        )
    }

    private func trackDecodeFailures(
        statusResponse: XAIVideoStatusResponse?,
        rawJSON: [String: Any]?,
        httpStatus: Int,
        rawBody: String,
        consecutiveFailures: Int,
        maxFailures: Int
    ) throws -> Int {
        guard statusResponse == nil,
              httpStatus >= 200,
              httpStatus < 300 else {
            return 0
        }

        let rawHasStatusSignal: Bool = {
            guard let json = rawJSON else { return false }
            for key in ["status", "state"] {
                if json[key] is String { return true }
            }
            return false
        }()

        guard !rawHasStatusSignal else { return 0 }

        let updated = consecutiveFailures + 1
        if updated >= maxFailures {
            throw LLMError.decodingError(
                message: "xAI video poll response could not be decoded after \(maxFailures) consecutive attempts. Last response: \(String(rawBody.prefix(500)))"
            )
        }
        return updated
    }

    // MARK: - Video Poll Status Resolution

    enum VideoPollStatus {
        case pending
        case done
        case expired
        case failed(String?)
    }

    func resolveVideoStatus(
        codable: XAIVideoStatusResponse?,
        rawJSON: [String: Any]?,
        httpStatus: Int
    ) -> VideoPollStatus {
        if let status = codable?.status?.lowercased(),
           let resolved = classifyVideoStatusString(status) {
            return resolved
        }

        if let json = rawJSON {
            for key in ["status", "state"] {
                if let val = json[key] as? String,
                   let resolved = classifyVideoStatusString(val.lowercased(), failureMessage: extractFailureMessage(from: json)) {
                    return resolved
                }
            }

            if extractVideoURL(codable: codable, rawJSON: rawJSON) != nil {
                return .done
            }
        }

        if httpStatus == 404 || httpStatus == 410 {
            return .expired
        }
        if httpStatus >= 500 {
            let message = extractFailureMessage(from: rawJSON)
            return .failed(message ?? "Server error (HTTP \(httpStatus))")
        }
        if httpStatus >= 400 {
            let message = extractFailureMessage(from: rawJSON)
            return .failed(message ?? "HTTP \(httpStatus)")
        }

        return .pending
    }

    func classifyVideoStatusString(_ status: String, failureMessage: String? = nil) -> VideoPollStatus? {
        switch status {
        case "done", "complete", "completed", "success":
            return .done
        case "expired":
            return .expired
        case "failed", "error":
            return .failed(failureMessage)
        case "pending", "in_progress", "processing", "queued":
            return .pending
        default:
            return nil
        }
    }

    func extractFailureMessage(from json: [String: Any]?) -> String? {
        guard let json else { return nil }

        if let message = nonEmptyMessage(json["message"]) {
            return message
        }
        if let errorText = nonEmptyMessage(json["error"]) {
            return errorText
        }

        if let errorObject = json["error"] as? [String: Any] {
            if let message = nonEmptyMessage(errorObject["message"]) {
                return message
            }
            if let detail = nonEmptyMessage(errorObject["detail"]) {
                return detail
            }
            if let reason = nonEmptyMessage(errorObject["reason"]) {
                return reason
            }
        }

        if let errors = json["errors"] as? [[String: Any]] {
            for item in errors {
                if let nested = extractFailureMessage(from: item) {
                    return nested
                }
            }
        }

        for nestedKey in ["response", "data", "result"] {
            if let nested = extractFailureMessage(from: json[nestedKey] as? [String: Any]) {
                return nested
            }
        }

        return nil
    }

    func nonEmptyMessage(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func extractVideoURL(codable: XAIVideoStatusResponse?, rawJSON: [String: Any]?) -> URL? {
        if let urlString = codable?.resolvedVideo?.url, let url = URL(string: urlString) {
            return url
        }

        guard let json = rawJSON else { return nil }

        if let video = json["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let response = json["response"] as? [String: Any],
           let video = response["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let result = json["result"] as? [String: Any] {
            if let video = result["video"] as? [String: Any],
               let urlString = video["url"] as? String,
               let url = URL(string: urlString) {
                return url
            }
            if let urlString = result["url"] as? String, let url = URL(string: urlString) {
                return url
            }
        }

        if let data = json["data"] as? [String: Any],
           let video = data["video"] as? [String: Any],
           let urlString = video["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }

        if let urlString = json["url"] as? String,
           let url = URL(string: urlString),
           urlString.contains("video") || urlString.contains(".mp4") || urlString.contains("vidgen") {
            return url
        }

        return nil
    }

    // MARK: - Video Request Building

    func buildVideoGenerationRequest(
        modelID: String,
        prompt: String,
        imageURL: String?,
        videoURL: String?,
        controls: GenerationControls
    ) throws -> URLRequest {
        let isVideoEdit = videoURL?.isEmpty == false
        let endpoint = isVideoEdit ? "videos/edits" : "videos/generations"

        var request = URLRequest(url: try validatedURL("\(baseURL)/\(endpoint)"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let videoControls = controls.xaiVideoGeneration

        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt
        ]

        if !isVideoEdit {
            if let duration = videoControls?.duration {
                body["duration"] = min(max(duration, 1), 15)
            }
            if let aspectRatio = videoControls?.aspectRatio {
                let supportedVideoRatios: Set<XAIAspectRatio> = [
                    .ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio3x2, .ratio2x3
                ]
                if supportedVideoRatios.contains(aspectRatio) {
                    body["aspect_ratio"] = aspectRatio.rawValue
                }
            }
            if let resolution = videoControls?.resolution {
                body["resolution"] = resolution.rawValue
            }
        }

        if let videoURL, !videoURL.isEmpty {
            body["video"] = ["url": videoURL]
        } else if let imageURL, !imageURL.isEmpty {
            body["image"] = ["url": imageURL]
        }

        applyProviderSpecificOverrides(controls: controls, body: &body)

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func downloadVideoToLocal(from url: URL) async throws -> (URL, String) {
        let result = try await VideoAttachmentUtility.downloadToLocal(
            from: url,
            networkManager: networkManager
        )
        return (result.localURL, result.mimeType)
    }

    // MARK: - Video URL Resolution

    func resolvedVideoURL(for video: VideoContent?) async throws -> String? {
        guard let video else { return nil }

        if let remote = remoteVideoURLString(video) {
            return remote
        }

        let r2PluginEnabled = await r2Uploader.isPluginEnabled()
        guard r2PluginEnabled else {
            throw LLMError.invalidRequest(
                message: "xAI local video input requires Cloudflare R2 Upload. Enable Settings \u{2192} Plugins \u{2192} Cloudflare R2 Upload and configure it, or attach a public HTTPS video URL."
            )
        }

        do {
            let uploadedURL = try await r2Uploader.uploadVideo(video)
            return uploadedURL.absoluteString
        } catch let error as CloudflareR2UploaderError {
            throw LLMError.invalidRequest(
                message: "\(error.localizedDescription)\n\nOpen Settings \u{2192} Plugins \u{2192} Cloudflare R2 Upload to complete the configuration."
            )
        } catch {
            throw error
        }
    }

    func remoteVideoURLString(_ video: VideoContent) -> String? {
        guard let url = video.url, isHTTPRemoteURL(url) else {
            return nil
        }
        return url.absoluteString
    }

    // MARK: - Video Input Extraction

    func videoInputForVideoGeneration(from messages: [Message]) -> VideoContent? {
        if let latestUserVideo = latestUserVideoInput(from: messages) {
            return latestUserVideo
        }

        if let latestUserRemoteVideo = latestUserMentionedRemoteVideoInput(from: messages) {
            return latestUserRemoteVideo
        }

        if let assistantVideo = firstVideoInput(from: messages, roles: [.assistant]) {
            return assistantVideo
        }

        if let olderUserVideo = firstVideoInput(from: messages, roles: [.user]) {
            return olderUserVideo
        }

        return firstMentionedRemoteVideoInput(from: messages, roles: [.user])
    }

    private func latestUserVideoInput(from messages: [Message]) -> VideoContent? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return firstVideoInput(in: latestUserMessage)
    }

    private func firstVideoInput(in message: Message) -> VideoContent? {
        for part in message.content {
            if case .video(let video) = part {
                return video
            }
        }
        return nil
    }

    private func firstVideoInput(from messages: [Message], roles: [MessageRole]) -> VideoContent? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let video = firstVideoInput(in: message) {
                return video
            }
        }
        return nil
    }

    private func latestUserMentionedRemoteVideoInput(from messages: [Message]) -> VideoContent? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return firstMentionedRemoteVideoInput(in: latestUserMessage)
    }

    private func firstMentionedRemoteVideoInput(from messages: [Message], roles: [MessageRole]) -> VideoContent? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let video = firstMentionedRemoteVideoInput(in: message) {
                return video
            }
        }
        return nil
    }

    private func firstMentionedRemoteVideoInput(in message: Message) -> VideoContent? {
        for part in message.content {
            guard case .text(let text) = part,
                  let url = firstRemoteVideoURLMention(in: text) else {
                continue
            }

            let inferred = VideoAttachmentUtility.resolveVideoFormat(contentType: nil, url: url)
            return VideoContent(mimeType: inferred.mimeType, data: nil, url: url, assetDisposition: .externalReference)
        }
        return nil
    }

    func firstRemoteVideoURLMention(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        for match in detector.matches(in: trimmed, options: [], range: range) {
            guard let url = match.url,
                  isHTTPRemoteURL(url),
                  looksLikeVideoRemoteURL(url) else {
                continue
            }
            return url
        }

        return nil
    }
}
