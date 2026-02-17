import Foundation

extension VertexAIAdapter {

    /// Veo video generation via `:predictLongRunning` + `:fetchPredictOperation` polling.
    func makeVideoGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        accessToken: String
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        guard let prompt = GoogleVideoGenerationCore.extractPrompt(from: messages) else {
            throw LLMError.invalidRequest(message: "Video generation requires a text prompt.")
        }

        let imageInput = GoogleVideoGenerationCore.extractImageInput(from: messages)
        let videoControls = controls.googleVideoGeneration

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // 1. Build and submit the generation request
                    let endpoint = "\(baseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(location)/publishers/google/models/\(modelID):predictLongRunning"
                    var request = URLRequest(url: URL(string: endpoint)!)
                    request.httpMethod = "POST"
                    request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                    var instance: [String: Any] = ["prompt": prompt]

                    if let image = imageInput,
                       let base64 = GoogleVideoGenerationCore.imageToBase64(image) {
                        instance["image"] = [
                            "bytesBase64Encoded": base64,
                            "mimeType": image.mimeType
                        ]
                    }

                    let parameters = GoogleVideoGenerationCore.buildVertexParameters(
                        controls: videoControls,
                        modelID: modelID
                    )

                    let body: [String: Any] = [
                        "instances": [instance],
                        "parameters": parameters
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (startData, _) = try await networkManager.sendRequest(request)
                    let rawStart = try? JSONSerialization.jsonObject(with: startData) as? [String: Any]
                    guard let operationName = rawStart?["name"] as? String, !operationName.isEmpty else {
                        let raw = String(data: startData, encoding: .utf8) ?? "(non-UTF-8)"
                        throw LLMError.decodingError(
                            message: "Vertex AI video generation did not return an operation name. Response: \(String(raw.prefix(500)))"
                        )
                    }

                    continuation.yield(.messageStart(id: operationName))

                    // 2. Poll using fetchPredictOperation
                    let pollIntervalNanoseconds: UInt64 = 10_000_000_000 // 10 seconds
                    let maxAttempts = 60 // ~10 minutes at 10s intervals

                    for attempt in 0..<maxAttempts {
                        try Task.checkCancellation()

                        if attempt > 0 {
                            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                        }

                        // Vertex uses POST fetchPredictOperation instead of GET on the operation URL
                        let pollEndpoint = "\(baseURL)/projects/\(serviceAccountJSON.projectID)/locations/\(location)/publishers/google/models/\(modelID):fetchPredictOperation"
                        var pollRequest = URLRequest(url: URL(string: pollEndpoint)!)
                        pollRequest.httpMethod = "POST"
                        pollRequest.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                        pollRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

                        let pollBody: [String: Any] = ["operationName": operationName]
                        pollRequest.httpBody = try JSONSerialization.data(withJSONObject: pollBody)

                        let (pollData, pollResponse) = try await networkManager.sendRawRequest(pollRequest)
                        let pollJSON = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any]

                        // Check for error in operation
                        if let error = pollJSON?["error"] as? [String: Any] {
                            let message = error["message"] as? String ?? "Video generation failed."
                            throw LLMError.providerError(code: "video_generation_failed", message: message)
                        }

                        // Non-2xx HTTP means something went wrong
                        if pollResponse.statusCode >= 400 {
                            let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                            throw LLMError.providerError(
                                code: "video_poll_error",
                                message: "Polling returned HTTP \(pollResponse.statusCode): \(String(raw.prefix(500)))"
                            )
                        }

                        let done = pollJSON?["done"] as? Bool ?? false
                        guard done else { continue }

                        // 3. Extract video from response
                        guard let response = pollJSON?["response"] as? [String: Any] else {
                            let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                            throw LLMError.decodingError(
                                message: "Vertex AI video generation completed but no response found. Response: \(String(raw.prefix(500)))"
                            )
                        }

                        // Vertex returns videos as base64 or GCS URI
                        guard let videos = response["videos"] as? [[String: Any]],
                              let firstVideo = videos.first else {
                            let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                            throw LLMError.decodingError(
                                message: "Vertex AI video generation completed but no videos found. Response: \(String(raw.prefix(500)))"
                            )
                        }

                        // Try inline base64 first
                        if let base64String = firstVideo["bytesBase64Encoded"] as? String,
                           let videoData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) {
                            let localURL = try GoogleVideoGenerationCore.saveVideoDataToLocal(
                                videoData,
                                mimeType: "video/mp4"
                            )
                            let videoContent = VideoContent(mimeType: "video/mp4", data: nil, url: localURL)
                            continuation.yield(.contentDelta(.video(videoContent)))
                            continuation.yield(.messageEnd(usage: nil))
                            continuation.finish()
                            return
                        }

                        // Try GCS URI
                        if let gcsUri = firstVideo["gcsUri"] as? String, !gcsUri.isEmpty {
                            let downloadURL = try convertGCSURIToHTTPS(gcsUri)
                            let (localURL, mimeType) = try await GoogleVideoGenerationCore.downloadVideoToLocal(
                                from: downloadURL,
                                networkManager: networkManager,
                                authHeader: (key: "Authorization", value: "Bearer \(accessToken)")
                            )
                            let videoContent = VideoContent(mimeType: mimeType, data: nil, url: localURL)
                            continuation.yield(.contentDelta(.video(videoContent)))
                            continuation.yield(.messageEnd(usage: nil))
                            continuation.finish()
                            return
                        }

                        let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                        throw LLMError.decodingError(
                            message: "Vertex AI video generation completed but video data could not be extracted. Response: \(String(raw.prefix(500)))"
                        )
                    }

                    throw LLMError.providerError(
                        code: "video_generation_timeout",
                        message: "Vertex AI video generation timed out after polling for ~10 minutes."
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

    /// Converts a `gs://bucket/path` URI to an HTTPS URL for the GCS JSON API.
    private func convertGCSURIToHTTPS(_ gcsUri: String) throws -> URL {
        let trimmed = gcsUri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("gs://") else {
            throw LLMError.decodingError(message: "Invalid GCS URI: \(trimmed)")
        }

        let withoutScheme = String(trimmed.dropFirst("gs://".count))
        guard let slashIndex = withoutScheme.firstIndex(of: "/") else {
            throw LLMError.decodingError(message: "Invalid GCS URI (no object path): \(trimmed)")
        }

        let bucket = String(withoutScheme[..<slashIndex])
        let objectPath = String(withoutScheme[withoutScheme.index(after: slashIndex)...])

        guard let encodedPath = objectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw LLMError.decodingError(message: "Invalid GCS object path: \(objectPath)")
        }

        let urlString = "https://storage.googleapis.com/storage/v1/b/\(bucket)/o/\(encodedPath)?alt=media"
        guard let url = URL(string: urlString) else {
            throw LLMError.decodingError(message: "Could not construct download URL from GCS URI: \(trimmed)")
        }

        return url
    }
}
