import Foundation

extension GeminiAdapter {

    func makeVideoGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        guard let prompt = GoogleVideoGenerationCore.extractPrompt(from: messages) else {
            throw LLMError.invalidRequest(message: "Video generation requires a text prompt.")
        }

        let imageInput = GoogleVideoGenerationCore.extractImageInput(from: messages)
        let videoControls = controls.googleVideoGeneration

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let modelPath = modelIDForPath(modelID)
                    let endpoint = "\(baseURL)/models/\(modelPath):predictLongRunning"

                    var instance: [String: Any] = ["prompt": prompt]

                    if let image = imageInput,
                       let base64 = try GoogleVideoGenerationCore.imageToBase64(image) {
                        instance["image"] = [
                            "inlineData": [
                                "mimeType": image.mimeType,
                                "data": base64
                            ]
                        ]
                    }

                    let parameters = GoogleVideoGenerationCore.buildGeminiParameters(
                        controls: videoControls,
                        modelID: modelID
                    )

                    let body: [String: Any] = [
                        "instances": [instance],
                        "parameters": parameters
                    ]
                    let request = try NetworkRequestFactory.makeJSONRequest(
                        url: validatedURL(endpoint),
                        headers: geminiHeaders(),
                        body: body
                    )

                    let (startData, _) = try await networkManager.sendRequest(request)
                    let rawStart = try? JSONSerialization.jsonObject(with: startData) as? [String: Any]
                    guard let operationName = rawStart?["name"] as? String, !operationName.isEmpty else {
                        let raw = String(data: startData, encoding: .utf8) ?? "(non-UTF-8)"
                        throw LLMError.decodingError(
                            message: "Gemini video generation did not return an operation name. Response: \(String(raw.prefix(500)))"
                        )
                    }

                    continuation.yield(.messageStart(id: operationName))

                    try await pollGeminiVideoOperation(
                        operationName: operationName,
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

    private func pollGeminiVideoOperation(
        operationName: String,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let pollIntervalNanoseconds: UInt64 = 10_000_000_000
        let maxAttempts = 60

        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()

            if attempt > 0 {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }

            let pollRequest = NetworkRequestFactory.makeRequest(
                url: try validatedURL("\(baseURL)/\(operationName)"),
                headers: geminiHeaders()
            )

            let (pollData, pollResponse) = try await networkManager.sendRawRequest(pollRequest)
            guard let pollJSON = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any] else {
                let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                throw LLMError.decodingError(
                    message: "Gemini video poll returned non-JSON response: \(String(raw.prefix(500)))"
                )
            }

            if let error = pollJSON["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Video generation failed."
                throw LLMError.providerError(code: "video_generation_failed", message: message)
            }

            if pollResponse.statusCode >= 400 {
                let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                throw LLMError.providerError(
                    code: "video_poll_error",
                    message: "Polling returned HTTP \(pollResponse.statusCode): \(String(raw.prefix(500)))"
                )
            }

            let done = pollJSON["done"] as? Bool ?? false
            guard done else { continue }

            guard let response = pollJSON["response"] as? [String: Any],
                  let generateVideoResponse = response["generateVideoResponse"] as? [String: Any],
                  let generatedSamples = generateVideoResponse["generatedSamples"] as? [[String: Any]],
                  let firstSample = generatedSamples.first,
                  let video = firstSample["video"] as? [String: Any],
                  let uriString = video["uri"] as? String,
                  !uriString.isEmpty else {
                let raw = String(data: pollData, encoding: .utf8) ?? "(non-UTF-8)"
                throw LLMError.decodingError(
                    message: "Gemini video generation completed but no video URI found. Response: \(String(raw.prefix(500)))"
                )
            }

            var downloadComponents = URLComponents(string: uriString)
            var queryItems = downloadComponents?.queryItems ?? []
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
            downloadComponents?.queryItems = queryItems

            guard let downloadURL = downloadComponents?.url else {
                throw LLMError.decodingError(message: "Invalid video download URI: \(uriString)")
            }

            let (localURL, mimeType) = try await VideoAttachmentUtility.downloadToLocal(
                from: downloadURL,
                networkManager: networkManager
            )

            let videoContent = VideoContent(mimeType: mimeType, data: nil, url: localURL)
            continuation.yield(.contentDelta(.video(videoContent)))
            continuation.yield(.messageEnd(usage: nil))
            continuation.finish()
            return
        }

        throw LLMError.providerError(
            code: "video_generation_timeout",
            message: "Gemini video generation timed out after polling for ~10 minutes."
        )
    }
}
