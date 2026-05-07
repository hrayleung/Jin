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

}
