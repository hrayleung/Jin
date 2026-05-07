import Foundation

extension XAIAdapter {

    // MARK: - Video Generation Stream

    func makeVideoGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let videoInput = XAIVideoInputSupport.videoInputForVideoGeneration(from: messages)
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

            let pollRequest = makeGETRequest(
                url: try validatedURL("\(baseURL)/videos/\(requestID)"),
                apiKey: apiKey,
                accept: nil,
                includeUserAgent: false
            )

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

            let status = XAIVideoPollingSupport.resolveStatus(
                codable: statusResponse,
                rawJSON: rawJSON,
                httpStatus: pollHTTPResponse.statusCode
            )

            switch status {
            case .done:
                consecutiveDecodeFailures = 0
                guard let videoURL = XAIVideoPollingSupport.extractVideoURL(codable: statusResponse, rawJSON: rawJSON) else {
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
                consecutiveDecodeFailures = try XAIVideoPollingSupport.trackDecodeFailures(
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

    // MARK: - Video Request Building

    func buildVideoGenerationRequest(
        modelID: String,
        prompt: String,
        imageURL: String?,
        videoURL: String?,
        controls: GenerationControls
    ) throws -> URLRequest {
        let components = XAIMediaRequestSupport.videoRequestComponents(
            modelID: modelID,
            prompt: prompt,
            imageURL: imageURL,
            videoURL: videoURL,
            controls: controls.xaiVideoGeneration
        )
        var body = components.body

        applyProviderSpecificOverrides(controls: controls, body: &body)

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/\(components.endpoint)"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            includeUserAgent: false
        )
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

        if let remote = XAIVideoInputSupport.remoteVideoURLString(video) {
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

}
