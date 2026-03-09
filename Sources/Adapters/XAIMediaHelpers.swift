import Foundation

extension XAIAdapter {

    // MARK: - Media Edit Mode

    enum MediaEditMode {
        case none
        case image
        case video
    }

    // MARK: - Media Prompt Building

    func mediaPrompt(from messages: [Message], mode: MediaEditMode) throws -> String {
        let userPrompts = userTextPrompts(from: messages)
        guard let latest = userPrompts.last else {
            throw LLMError.invalidRequest(message: "xAI media generation requires a text prompt.")
        }

        guard mode != .none else {
            return latest
        }

        let recentPrompts = Array(userPrompts.suffix(6))
        let originalPrompt = recentPrompts.first ?? latest
        let latestPrompt = recentPrompts.last ?? latest
        let priorEdits = Array(recentPrompts.dropFirst().dropLast())

        if mode == .image, userPrompts.count < 2 {
            return latest
        }

        if mode == .image,
           priorEdits.isEmpty,
           originalPrompt.caseInsensitiveCompare(latestPrompt) == .orderedSame {
            return latest
        }

        let continuityInstruction: String = switch mode {
        case .image:
            "Keep the main subject, composition, and scene continuity unless explicitly changed."
        case .video:
            "Keep the main subject, composition, camera motion, and timing continuity unless explicitly changed."
        case .none:
            ""
        }

        let mediaLabel: String = switch mode {
        case .image: "image"
        case .video: "video"
        case .none: "media"
        }

        var lines: [String] = [
            "Edit the provided input \(mediaLabel).",
            continuityInstruction,
            "",
            "Original request:",
            originalPrompt
        ]

        if !priorEdits.isEmpty {
            lines.append("")
            lines.append("Edits already applied:")
            for (idx, edit) in priorEdits.enumerated() {
                lines.append("\(idx + 1). \(edit)")
            }
        }

        lines.append("")
        lines.append("Apply this new edit now:")
        lines.append(latestPrompt)

        return lines.joined(separator: "\n")
    }

    func userTextPrompts(from messages: [Message]) -> [String] {
        messages.compactMap { message in
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
    }

    // MARK: - Image URL Extraction

    func imageURLForImageGeneration(from messages: [Message]) throws -> String? {
        if let latestUserImageURL = try latestUserImageURL(from: messages) {
            return latestUserImageURL
        }

        if let assistantImageURL = try firstImageURLString(from: messages, roles: [.assistant]) {
            return assistantImageURL
        }

        return try firstImageURLString(from: messages, roles: [.user])
    }

    private func latestUserImageURL(from messages: [Message]) throws -> String? {
        guard let latestUserMessage = messages.reversed().first(where: { $0.role == .user }) else {
            return nil
        }
        return try firstImageURLString(in: latestUserMessage)
    }

    private func firstImageURLString(in message: Message) throws -> String? {
        for part in message.content {
            if case .image(let image) = part,
               let urlString = try imageURLString(image) {
                return urlString
            }
        }
        return nil
    }

    private func firstImageURLString(from messages: [Message], roles: [MessageRole]) throws -> String? {
        let roleSet = Set(roles)

        for message in messages.reversed() where roleSet.contains(message.role) {
            if let urlString = try firstImageURLString(in: message) {
                return urlString
            }
        }
        return nil
    }

    func imageURLString(_ image: ImageContent) throws -> String? {
        if let data = image.data {
            return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
        }

        if let url = image.url {
            if url.isFileURL {
                let data = try resolveFileData(from: url)
                return "data:\(image.mimeType);base64,\(data.base64EncodedString())"
            }
            return url.absoluteString
        }

        return nil
    }

    // MARK: - URL Classification

    func isHTTPRemoteURL(_ url: URL) -> Bool {
        guard !url.isFileURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }

    func looksLikeVideoRemoteURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let knownVideoExtensions: Set<String> = [
            "mp4", "m4v", "mov", "webm", "avi", "mkv",
            "mpeg", "mpg", "wmv", "flv", "3gp", "3gpp"
        ]
        if knownVideoExtensions.contains(ext) {
            return true
        }

        let lower = url.absoluteString.lowercased()
        let markers = [
            ".mp4", ".m4v", ".mov", ".webm", ".avi", ".mkv",
            ".mpeg", ".mpg", ".wmv", ".flv", ".3gp", ".3gpp",
            "/video", "-video", "_video", "video="
        ]
        return markers.contains { lower.contains($0) }
    }

    // MARK: - Image Output Resolution

    func resolveImageOutputs(from items: [XAIMediaItem]) -> [ImageContent] {
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

    func inferImageMIMEType(from url: URL) -> String? {
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
}
