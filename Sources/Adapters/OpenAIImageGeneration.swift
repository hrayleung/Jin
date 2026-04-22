import Alamofire
import Foundation

private struct PreparedOpenAIUploadImage {
    let data: Data
    let mimeType: String
    let filename: String
}

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

    // MARK: - Request Building

    private func buildImageGenerationRequest(
        modelID: String,
        prompt: String,
        inputImages: [ImageContent],
        controls: GenerationControls
    ) async throws -> URLRequest {
        guard let profile = OpenAIImageModelSupport.profile(for: modelID) else {
            throw LLMError.invalidRequest(message: "Unsupported OpenAI image model: \(modelID)")
        }

        let isImageEdit = profile.supportsEdits && !inputImages.isEmpty

        if isImageEdit, profile.usesMultipartEdits {
            return try await buildMultipartImageEditRequest(
                modelID: modelID,
                prompt: prompt,
                inputImages: inputImages,
                controls: controls
            )
        }

        let endpoint = isImageEdit ? "images/edits" : "images/generations"
        let imageControls = controls.openaiImageGeneration

        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
        ]

        if let count = imageControls?.count, count > 0 {
            body["n"] = min(max(count, 1), 10)
        }

        if let size = imageControls?.size,
           OpenAIImageModelSupport.validate(size: size, for: modelID) == nil {
            body["size"] = size.rawValue
        }

        if let quality = imageControls?.quality,
           profile.qualityOptions.contains(quality) {
            body["quality"] = quality.rawValue
        }

        if profile.supportsStyle, let style = imageControls?.style {
            body["style"] = style.rawValue
        }

        if !profile.backgroundOptions.isEmpty,
           let background = imageControls?.background,
           profile.backgroundOptions.contains(background) {
            body["background"] = background.rawValue
        }

        if profile.supportsOutputFormat, let outputFormat = imageControls?.outputFormat {
            body["output_format"] = outputFormat.rawValue
        }

        if profile.supportsOutputCompression,
           let compression = imageControls?.outputCompression,
           let format = imageControls?.outputFormat,
           format == .jpeg || format == .webp {
            body["output_compression"] = min(max(compression, 0), 100)
        }

        if profile.supportsModeration, let moderation = imageControls?.moderation {
            body["moderation"] = moderation.rawValue
        }

        if isImageEdit,
           profile.supportsInputFidelity,
           let fidelity = imageControls?.inputFidelity {
            body["input_fidelity"] = fidelity.rawValue
        }

        if isImageEdit,
           let firstImage = inputImages.first,
           let imageURL = imageURLString(firstImage),
           !imageURL.isEmpty {
            body["images"] = [["image_url": imageURL]]
        }

        if !profile.isGPTImageModel {
            body["response_format"] = "b64_json"
        }

        if let user = imageControls?.user?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            body["user"] = user
        }

        for (key, value) in controls.providerSpecific {
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/\(endpoint)"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            includeUserAgent: false
        )
    }

    private func buildMultipartImageEditRequest(
        modelID: String,
        prompt: String,
        inputImages: [ImageContent],
        controls: GenerationControls
    ) async throws -> URLRequest {
        let imageControls = controls.openaiImageGeneration
        let preparedImages = try await preparedUploadImages(from: inputImages)

        guard !preparedImages.isEmpty else {
            throw LLMError.invalidRequest(message: "OpenAI image editing requires at least one readable input image.")
        }

        let url = try validatedURL("\(baseURL)/images/edits")
        let headers = NetworkRequestFactory.bearerHeaders(apiKey: apiKey)

        return try NetworkRequestFactory.makeMultipartRequest(
            url: url,
            headers: headers
        ) { formData in
            appendMultipartField("model", value: modelID, formData: formData)
            appendMultipartField("prompt", value: prompt, formData: formData)

            if let count = imageControls?.count, count > 0 {
                appendMultipartField("n", value: min(max(count, 1), 10), formData: formData)
            }

            if let size = imageControls?.size,
               OpenAIImageModelSupport.validate(size: size, for: modelID) == nil {
                appendMultipartField("size", value: size.rawValue, formData: formData)
            }

            if let quality = imageControls?.quality,
               OpenAIImageModelSupport.profile(for: modelID)?.qualityOptions.contains(quality) == true {
                appendMultipartField("quality", value: quality.rawValue, formData: formData)
            }

            if let background = imageControls?.background,
               OpenAIImageModelSupport.profile(for: modelID)?.backgroundOptions.contains(background) == true {
                appendMultipartField("background", value: background.rawValue, formData: formData)
            }

            if let outputFormat = imageControls?.outputFormat {
                appendMultipartField("output_format", value: outputFormat.rawValue, formData: formData)
            }

            if let compression = imageControls?.outputCompression,
               let format = imageControls?.outputFormat,
               format == .jpeg || format == .webp {
                appendMultipartField("output_compression", value: min(max(compression, 0), 100), formData: formData)
            }

            if let moderation = imageControls?.moderation {
                appendMultipartField("moderation", value: moderation.rawValue, formData: formData)
            }

            if let user = imageControls?.user?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
                appendMultipartField("user", value: user, formData: formData)
            }

            for image in preparedImages {
                formData.append(
                    image.data,
                    withName: "image[]",
                    fileName: image.filename,
                    mimeType: image.mimeType
                )
            }

            for (key, value) in controls.providerSpecific {
                appendMultipartField(key, value: value.value, formData: formData)
            }
        }
    }

    private func appendMultipartField(_ name: String, value: Any, formData: MultipartFormData) {
        guard let stringValue = multipartFieldString(for: value) else { return }
        formData.append(Data(stringValue.utf8), withName: name)
    }

    private func multipartFieldString(for value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let float as Float:
            return String(float)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        default:
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let jsonString = String(data: data, encoding: .utf8) else {
                return nil
            }
            return jsonString
        }
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

    // MARK: - Image Input Extraction

    private func inputImagesForImageGeneration(from messages: [Message]) -> [ImageContent] {
        if let latestUserImages = latestImages(in: messages, roles: [.user], requireLatestMessageOnly: true) {
            return latestUserImages
        }

        if let assistantImages = latestImages(in: messages, roles: [.assistant], requireLatestMessageOnly: false) {
            return assistantImages
        }

        return latestImages(in: messages, roles: [.user], requireLatestMessageOnly: false) ?? []
    }

    private func latestImages(
        in messages: [Message],
        roles: [MessageRole],
        requireLatestMessageOnly: Bool
    ) -> [ImageContent]? {
        let roleSet = Set(roles)

        if requireLatestMessageOnly {
            guard let latestMessage = messages.last(where: { roleSet.contains($0.role) }) else {
                return nil
            }
            let images = images(in: latestMessage)
            return images.isEmpty ? nil : images
        }

        for message in messages.reversed() where roleSet.contains(message.role) {
            let images = images(in: message)
            if !images.isEmpty {
                return images
            }
        }

        return nil
    }

    private func images(in message: Message) -> [ImageContent] {
        message.content.compactMap { part in
            guard case .image(let image) = part else { return nil }
            return image
        }
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

    private func preparedUploadImages(from images: [ImageContent]) async throws -> [PreparedOpenAIUploadImage] {
        var prepared: [PreparedOpenAIUploadImage] = []

        for (index, image) in images.enumerated() {
            let data = try await resolvedImageData(forUpload: image)
            let filename = preferredImageFilename(for: image, index: index + 1)
            prepared.append(
                PreparedOpenAIUploadImage(
                    data: data,
                    mimeType: image.mimeType,
                    filename: filename
                )
            )
        }

        return prepared
    }

    private func resolvedImageData(forUpload image: ImageContent) async throws -> Data {
        if let data = image.data {
            return data
        }

        if let url = image.url {
            if url.isFileURL {
                return try resolveFileData(from: url)
            }
            let request = NetworkRequestFactory.makeRequest(url: url, method: "GET")
            let (data, _) = try await networkManager.sendRequest(request)
            return data
        }

        throw LLMError.invalidRequest(message: "OpenAI image editing requires a readable input image.")
    }

    private func preferredImageFilename(for image: ImageContent, index: Int) -> String {
        if let url = image.url {
            let lastPath = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !lastPath.isEmpty, url.pathExtension.isEmpty == false {
                return lastPath
            }
        }

        let ext = fileExtension(for: image.mimeType) ?? "png"
        return "reference-\(index).\(ext)"
    }

    private func fileExtension(for mimeType: String) -> String? {
        switch normalizedMIMEType(mimeType) {
        case "image/png":
            return "png"
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/webp":
            return "webp"
        case "image/gif":
            return "gif"
        default:
            return nil
        }
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
                return ImageContent(mimeType: mime, data: nil, url: url, assetDisposition: .managed)
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
