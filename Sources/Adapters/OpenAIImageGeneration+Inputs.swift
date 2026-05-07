import Foundation

struct PreparedOpenAIUploadImage {
    let data: Data
    let mimeType: String
    let filename: String
}

extension OpenAIAdapter {
    func extractImagePrompt(from messages: [Message]) -> String {
        let userPrompts = messages.compactMap { message -> String? in
            guard message.role == .user else { return nil }
            let text = message.content.compactMap { part -> String? in
                guard case .text(let value) = part else { return nil }
                return value.trimmedNonEmpty
            }
            .joined(separator: "\n\n")
            return text.trimmedNonEmpty
        }
        return userPrompts.last ?? ""
    }

    func inputImagesForImageGeneration(from messages: [Message]) -> [ImageContent] {
        if let latestUserImages = latestImages(in: messages, roles: [.user], requireLatestMessageOnly: true) {
            return latestUserImages
        }

        if let assistantImages = latestImages(in: messages, roles: [.assistant], requireLatestMessageOnly: false) {
            return assistantImages
        }

        return latestImages(in: messages, roles: [.user], requireLatestMessageOnly: false) ?? []
    }

    func imageURLString(_ image: ImageContent) -> String? {
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

    func preparedUploadImages(from images: [ImageContent]) async throws -> [PreparedOpenAIUploadImage] {
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
            if let lastPath = url.lastPathComponent.trimmedNonEmpty, url.pathExtension.isEmpty == false {
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
}
