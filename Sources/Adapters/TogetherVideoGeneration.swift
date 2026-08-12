import Foundation

extension TogetherAdapter {
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
                    let startJSON = try decodeVideoJSONObject(startData)

                    if let failure = videoFailureMessage(from: startJSON) {
                        throw LLMError.providerError(code: "video_generation_failed", message: failure)
                    }

                    guard let jobID = extractVideoJobID(from: startJSON) else {
                        let raw = String(data: startData, encoding: .utf8) ?? "(non-UTF-8)"
                        throw LLMError.decodingError(
                            message: "Together video generation did not return a job ID. Response: \(String(raw.prefix(500)))"
                        )
                    }

                    continuation.yield(.messageStart(id: jobID))

                    try await pollVideoUntilDone(
                        jobID: jobID,
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

    func isVideoGenerationModel(_ modelID: String) -> Bool {
        if providerConfig.models.first(where: { $0.id == modelID })?.capabilities.contains(.videoGeneration) == true {
            return true
        }
        if let resolved = providerConfig.models.first(where: { $0.id.caseInsensitiveCompare(modelID) == .orderedSame }) {
            let settings = ModelSettingsResolver.resolve(model: resolved, providerType: .together)
            if settings.capabilities.contains(.videoGeneration) {
                return true
            }
        }
        if ModelCatalog.entry(for: modelID, provider: .together)?.capabilities.contains(.videoGeneration) == true {
            return true
        }
        return TogetherVideoModelSupport.isVideoGenerationModelID(modelID)
    }

    func videoGenerationPrompt(from messages: [Message]) throws -> String {
        for message in messages.reversed() where message.role == .user {
            let text = message.content.compactMap { part -> String? in
                guard case .text(let value) = part else { return nil }
                return value.trimmedNonEmpty
            }
            .joined(separator: "\n\n")

            if let text = text.trimmedNonEmpty {
                return text
            }
        }

        throw LLMError.invalidRequest(message: "Together video generation requires a text prompt.")
    }

    func videoGenerationImages(from messages: [Message]) -> [ImageContent] {
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

    func latestUserImageInputs(from messages: [Message]) -> [ImageContent]? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        let images = imageInputs(in: latestUserMessage)
        return images.isEmpty ? nil : images
    }

    func imageInputs(in message: Message) -> [ImageContent] {
        message.content.compactMap { part in
            guard case .image(let image) = part else { return nil }
            return image
        }
    }
}
