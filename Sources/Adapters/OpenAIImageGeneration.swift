import Foundation

// MARK: - OpenAI Image Generation

extension OpenAIAdapter {

    /// Known GPT Image model IDs.
    static let imageGenerationModelIDs: Set<String> = [
        "gpt-image-1",
        "gpt-image-1.5",
        "gpt-image-1-mini",
        "dall-e-2",
        "dall-e-3",
    ]

    /// Models that support the `/images/edits` endpoint.
    /// Note: `dall-e-3` does NOT support image editing.
    private static let imageEditSupportedModelIDs: Set<String> = [
        "gpt-image-1",
        "gpt-image-1.5",
        "gpt-image-1-mini",
        "dall-e-2",
    ]

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
        let imageURL = imageURLForImageGeneration(from: messages)
        let prompt = extractImagePrompt(from: messages)

        guard !prompt.isEmpty else {
            throw LLMError.invalidRequest(message: "OpenAI image generation requires a text prompt.")
        }

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

    // MARK: - Request Building

    private func buildImageGenerationRequest(
        modelID: String,
        prompt: String,
        imageURL: String?,
        controls: GenerationControls
    ) throws -> URLRequest {
        let lowerModel = modelID.lowercased()
        let modelSupportsEdit = Self.imageEditSupportedModelIDs.contains(lowerModel)
        let isImageEdit = modelSupportsEdit && (imageURL?.isEmpty == false)
        let endpoint = isImageEdit ? "images/edits" : "images/generations"

        var request = URLRequest(url: try validatedURL("\(baseURL)/\(endpoint)"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let imageControls = controls.openaiImageGeneration
        let isGPTImageModel = lowerModel.hasPrefix("gpt-image")
        let isDallE3 = lowerModel.hasPrefix("dall-e-3")

        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
        ]

        // n (number of images)
        if let count = imageControls?.count, count > 0 {
            body["n"] = min(max(count, 1), 10)
        }

        // Image input for edits — JSON schema expects `images` array of objects
        if isImageEdit, let imageURL, !imageURL.isEmpty {
            body["images"] = [["image_url": imageURL]]
        }

        // Size
        if let size = imageControls?.size {
            body["size"] = size.rawValue
        }

        // Quality
        if let quality = imageControls?.quality {
            body["quality"] = quality.rawValue
        }

        // Style (DALL-E 3 only)
        if isDallE3, let style = imageControls?.style {
            body["style"] = style.rawValue
        }

        // GPT Image model-specific parameters
        if isGPTImageModel {
            // Background
            if let background = imageControls?.background {
                body["background"] = background.rawValue
            }

            // Output format
            if let outputFormat = imageControls?.outputFormat {
                body["output_format"] = outputFormat.rawValue
            }

            // Output compression (0-100, only for jpeg/webp)
            if let compression = imageControls?.outputCompression,
               let format = imageControls?.outputFormat,
               format == .jpeg || format == .webp {
                body["output_compression"] = min(max(compression, 0), 100)
            }

            // Moderation
            if let moderation = imageControls?.moderation {
                body["moderation"] = moderation.rawValue
            }

            // Input fidelity (gpt-image-1 only, applies to edits)
            if isImageEdit, lowerModel == "gpt-image-1",
               let fidelity = imageControls?.inputFidelity {
                body["input_fidelity"] = fidelity.rawValue
            }
        }

        // response_format: use b64_json for GPT image models; DALL-E models support url or b64_json
        if !isGPTImageModel {
            body["response_format"] = "b64_json"
        }

        // User
        if let user = imageControls?.user?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            body["user"] = user
        }

        // Provider-specific overrides
        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Prompt Extraction

    private func extractImagePrompt(from messages: [Message]) -> String {
        let userPrompts = messages.compactMap { message -> String? in
            guard message.role == .user else { return nil }
            let text = message.content.compactMap { part -> String? in
                guard case .text(let value) = part else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return userPrompts.last ?? ""
    }

    // MARK: - Image URL Extraction

    private func imageURLForImageGeneration(from messages: [Message]) -> String? {
        // Check the latest user message for an image first
        if let latestUserMessage = messages.reversed().first(where: { $0.role == .user }),
           let urlString = firstImageURLString(in: latestUserMessage) {
            return urlString
        }

        // Then check assistant messages (e.g., for iterative edits)
        if let urlString = firstImageURLString(from: messages, roles: [.assistant]) {
            return urlString
        }

        // Finally check all user messages
        return firstImageURLString(from: messages, roles: [.user])
    }

    private func firstImageURLString(in message: Message) -> String? {
        for part in message.content {
            if case .image(let image) = part,
               let urlString = imageURLString(image) {
                return urlString
            }
        }
        return nil
    }

    private func firstImageURLString(from messages: [Message], roles: [MessageRole]) -> String? {
        let roleSet = Set(roles)
        for message in messages.reversed() where roleSet.contains(message.role) {
            if let urlString = firstImageURLString(in: message) {
                return urlString
            }
        }
        return nil
    }

    private func imageURLString(_ image: ImageContent) -> String? {
        if let data = image.data {
            return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
        }
        if let url = image.url {
            if url.isFileURL {
                guard let data = try? resolveFileData(from: url) else { return nil }
                return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
            }
            return url.absoluteString
        }
        return nil
    }

    // MARK: - Response Parsing

    private func resolveImageOutputs(
        from items: [OpenAIImageItem],
        controls: GenerationControls
    ) -> [ImageContent] {
        let outputFormat = controls.openaiImageGeneration?.outputFormat
        let defaultMIME = outputFormat?.mimeType ?? "image/png"

        return items.compactMap { item in
            if let b64 = item.b64Json, let data = Data(base64Encoded: b64) {
                return ImageContent(mimeType: defaultMIME, data: data, url: nil)
            }
            if let urlString = item.url, let url = URL(string: urlString) {
                let mime = inferImageMIMEType(from: url) ?? defaultMIME
                return ImageContent(mimeType: mime, data: nil, url: url)
            }
            return nil
        }
    }

    private func inferImageMIMEType(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return nil
        }
    }
}

// MARK: - Response Types

struct OpenAIImageGenerationResponse: Codable {
    let created: Int?
    let data: [OpenAIImageItem]?
    let error: OpenAIImageAPIError?
}

struct OpenAIImageItem: Codable {
    let url: String?
    let b64Json: String?
    let revisedPrompt: String?
}

struct OpenAIImageAPIError: Codable {
    let code: String?
    let message: String
}
