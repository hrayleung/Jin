import Foundation

// MARK: - OpenAI Image Generation

extension OpenAIAdapter {

    /// Known OpenAI image-generation model IDs.
    static let imageGenerationModelIDs: Set<String> = OpenAIImageModelSupport.imageGenerationModelIDs

    /// Models that support the `/images/edits` endpoint.
    static let imageEditSupportedModelIDs: Set<String> = OpenAIImageModelSupport.imageEditSupportedModelIDs

    func isImageGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.imageGeneration) == true {
            return true
        }
        return isImageGenerationModelID(modelID.lowercased())
    }

    func isImageGenerationModelID(_ lowerModelID: String) -> Bool {
        Self.imageGenerationModelIDs.contains(lowerModelID)
    }

    func makeImageGenerationStream(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let inputImages = inputImagesForImageGeneration(from: messages)
        let prompt = extractImagePrompt(from: messages)

        guard !prompt.isEmpty else {
            throw LLMError.invalidRequest(message: "OpenAI image generation requires a text prompt.")
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await buildImageGenerationRequest(
                        modelID: modelID,
                        prompt: prompt,
                        inputImages: inputImages,
                        controls: controls
                    )
                    let (data, _) = try await networkManager.sendRequest(request)

                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let response = try decoder.decode(OpenAIImageGenerationResponse.self, from: data)

                    if let error = response.error {
                        throw LLMError.providerError(
                            code: error.code ?? "image_generation_failed",
                            message: error.message
                        )
                    }

                    let images = resolveImageOutputs(from: response.data ?? [], controls: controls)
                    guard !images.isEmpty else {
                        throw LLMError.decodingError(message: "OpenAI image generation returned no image output.")
                    }

                    continuation.yield(.messageStart(id: "img_\(UUID().uuidString)"))
                    for image in images {
                        continuation.yield(.contentDelta(.image(image)))
                    }
                    if let revisedPrompt = response.data?.first?.revisedPrompt {
                        continuation.yield(.contentDelta(.text(revisedPrompt)))
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
}
