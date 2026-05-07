import Foundation

extension ClaudeManagedAgentRequestSupport {
    static func userContentBlocks(from message: Message) throws -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        for part in message.content {
            switch part {
            case .text(let text):
                blocks.append(textBlock(text))
            case .quote(let quote):
                blocks.append(textBlock(quote.quotedText))
            case .image(let image):
                if let block = try imageBlock(image) {
                    blocks.append(block)
                }
            case .file(let file):
                if let block = try fileBlock(file) {
                    blocks.append(block)
                }
            case .video(let video):
                blocks.append(textBlock(unsupportedVideoInputNotice(
                    video,
                    providerName: "Claude Managed Agents",
                    apiName: "Managed Agents"
                )))
            case .audio:
                blocks.append(textBlock("[Audio attachment]"))
            case .thinking, .redactedThinking:
                break
            }
        }

        return blocks.isEmpty ? continueContentBlocks() : blocks
    }

    private static func textBlock(_ text: String) -> [String: Any] {
        [
            "type": "text",
            "text": text
        ]
    }

    private static func imageBlock(_ image: ImageContent) throws -> [String: Any]? {
        guard let data = try attachmentData(existing: image.data, url: image.url) else {
            return nil
        }

        return [
            "type": "image",
            "source": base64Source(mediaType: image.mimeType, data: data)
        ]
    }

    private static func fileBlock(_ file: FileContent) throws -> [String: Any]? {
        let normalizedFileMIMEType = normalizedMIMEType(file.mimeType)

        if normalizedFileMIMEType == "application/pdf",
           let data = try attachmentData(existing: file.data, url: file.url) {
            return [
                "type": "document",
                "source": base64Source(mediaType: "application/pdf", data: data)
            ]
        }

        return textBlock(AttachmentPromptRenderer.fallbackText(for: file))
    }

    private static func attachmentData(existing data: Data?, url: URL?) throws -> Data? {
        if let data {
            return data
        }
        if let url, url.isFileURL {
            return try resolveFileData(from: url)
        }
        return nil
    }

    private static func base64Source(mediaType: String, data: Data) -> [String: Any] {
        [
            "type": "base64",
            "media_type": mediaType,
            "data": data.base64EncodedString()
        ]
    }
}
