import Foundation

enum XAIMediaImageSupport {
    static func imageURLForImageGeneration(
        from messages: [Message],
        fileDataResolver: (URL) throws -> Data = resolveFileData(from:)
    ) throws -> String? {
        if let latestUserImageURL = try latestUserImageURL(from: messages, fileDataResolver: fileDataResolver) {
            return latestUserImageURL
        }

        if let assistantImageURL = try firstImageURLString(from: messages, roles: [.assistant], fileDataResolver: fileDataResolver) {
            return assistantImageURL
        }

        return try firstImageURLString(from: messages, roles: [.user], fileDataResolver: fileDataResolver)
    }

    static func imageURLString(
        _ image: ImageContent,
        fileDataResolver: (URL) throws -> Data = resolveFileData(from:)
    ) throws -> String? {
        if let data = image.data {
            return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
        }

        if let url = image.url {
            if url.isFileURL {
                let data = try fileDataResolver(url)
                return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
            }
            return url.absoluteString
        }

        return nil
    }

    static func resolveImageOutputs(from items: [XAIMediaItem]) -> [ImageContent] {
        var out: [ImageContent] = []
        out.reserveCapacity(items.count)

        for item in items {
            if let b64 = item.b64JSON,
               let data = Data(base64Encoded: b64) {
                out.append(ImageContent(mimeType: item.mimeType ?? "image/png", data: data, url: nil))
                continue
            }

            if let rawURL = item.resolvedURL,
               let url = URL(string: rawURL) {
                let mime = item.mimeType ?? inferImageMIMEType(from: url) ?? "image/png"
                out.append(ImageContent(mimeType: mime, data: nil, url: url, assetDisposition: .managed))
            }
        }

        return out
    }

    static func inferImageMIMEType(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        default:
            return nil
        }
    }

    private static func latestUserImageURL(
        from messages: [Message],
        fileDataResolver: (URL) throws -> Data
    ) throws -> String? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return try firstImageURLString(in: latestUserMessage, fileDataResolver: fileDataResolver)
    }

    private static func firstImageURLString(
        in message: Message,
        fileDataResolver: (URL) throws -> Data
    ) throws -> String? {
        for part in message.content {
            if case .image(let image) = part,
               let urlString = try imageURLString(image, fileDataResolver: fileDataResolver) {
                return urlString
            }
        }
        return nil
    }

    private static func firstImageURLString(
        from messages: [Message],
        roles: [MessageRole],
        fileDataResolver: (URL) throws -> Data
    ) throws -> String? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let urlString = try firstImageURLString(in: message, fileDataResolver: fileDataResolver) {
                return urlString
            }
        }
        return nil
    }
}
