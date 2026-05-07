import Foundation

extension XAIAdapter {
    func makeImageGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let imageURL = try imageURLForImageGeneration(from: messages)
        let prompt = try mediaPrompt(
            from: messages,
            mode: imageURL?.isEmpty == false ? .image : .none
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildImageGenerationRequest(
                        modelID: modelID,
                        prompt: prompt,
                        imageURL: imageURL,
                        controls: controls
                    )
                    let (data, _) = try await networkManager.sendRequest(request)

                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let response = try decoder.decode(XAIImageGenerationResponse.self, from: data)

                    if let error = response.error {
                        throw LLMError.providerError(code: error.code ?? "image_generation_failed", message: error.message)
                    }

                    let images = resolveImageOutputs(from: response.mediaItems)
                    guard !images.isEmpty else {
                        throw LLMError.decodingError(message: "xAI image generation returned no image output.")
                    }

                    continuation.yield(.messageStart(id: response.resolvedID ?? "img_\(UUID().uuidString)"))
                    for image in images {
                        continuation.yield(.contentDelta(.image(image)))
                    }
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

    private func buildImageGenerationRequest(
        modelID: String,
        prompt: String,
        imageURL: String?,
        controls: GenerationControls
    ) throws -> URLRequest {
        let components = XAIMediaRequestSupport.imageRequestComponents(
            modelID: modelID,
            prompt: prompt,
            imageURL: imageURL,
            controls: controls.xaiImageGeneration
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
}
