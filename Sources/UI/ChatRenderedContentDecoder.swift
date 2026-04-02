import Foundation

enum ChatRenderedContentDecoder {
    static func renderedContentParts(from content: [ContentPart], messageID: UUID) -> [RenderedContentPart] {
        content.enumerated().map { index, part in
            renderedContentPart(from: part, messageID: messageID, partIndex: index)
        }
    }

    static func renderedContentParts(from contentData: Data, messageID: UUID) -> [RenderedContentPart]? {
        guard let rawParts = (try? JSONSerialization.jsonObject(with: contentData)) as? [[String: Any]] else {
            return nil
        }

        var parts: [RenderedContentPart] = []
        parts.reserveCapacity(rawParts.count)

        for (index, rawPart) in rawParts.enumerated() {
            if let part = renderedContentPart(from: rawPart, messageID: messageID, partIndex: index) {
                parts.append(part)
            }
        }

        return parts
    }

    private static func renderedContentPart(
        from part: ContentPart,
        messageID: UUID,
        partIndex: Int
    ) -> RenderedContentPart {
        let deferredSource = DeferredMessagePartReference(messageID: messageID, partIndex: partIndex)

        switch part {
        case .text(let text):
            return .text(text)
        case .quote(let quote):
            return .quote(quote)
        case .image(let image):
            return .image(
                RenderedImageContent(
                    mimeType: image.mimeType,
                    inlineData: image.data,
                    url: image.url,
                    assetDisposition: image.assetDisposition,
                    deferredSource: image.data == nil ? deferredSource : nil
                )
            )
        case .video(let video):
            return .video(video)
        case .file(let file):
            return .file(
                RenderedFileContent(
                    mimeType: file.mimeType,
                    filename: file.filename,
                    url: file.url,
                    extractedText: file.extractedText,
                    hasDeferredExtractedText: file.extractedText == nil,
                    deferredSource: file.extractedText == nil ? deferredSource : nil
                )
            )
        case .audio(let audio):
            return .audio(audio)
        case .thinking(let thinking):
            return .thinking(thinking)
        case .redactedThinking(let thinking):
            return .redactedThinking(thinking)
        }
    }

    private static func renderedContentPart(
        from rawPart: [String: Any],
        messageID: UUID,
        partIndex: Int
    ) -> RenderedContentPart? {
        guard let type = rawPart["type"] as? String else { return nil }
        let deferredSource = DeferredMessagePartReference(messageID: messageID, partIndex: partIndex)

        switch type {
        case "text":
            return decodeText(rawPart)
        case "quote":
            return decodeQuote(rawPart)
        case "image":
            return decodeImage(rawPart, deferredSource: deferredSource)
        case "video":
            return decodeVideo(rawPart)
        case "file":
            return decodeFile(rawPart, deferredSource: deferredSource)
        case "audio":
            return decodeAudio(rawPart)
        case "thinking":
            return decodeThinking(rawPart)
        case "redactedThinking":
            return decodeRedactedThinking(rawPart)
        default:
            return nil
        }
    }

    private static func decodeText(_ rawPart: [String: Any]) -> RenderedContentPart? {
        guard let text = rawPart["text"] as? String else { return nil }
        return .text(text)
    }

    private static func decodeQuote(_ rawPart: [String: Any]) -> RenderedContentPart? {
        guard let quote = rawPart["quote"] as? [String: Any],
              let sourceMessageIDString = quote["sourceMessageID"] as? String,
              let sourceMessageID = UUID(uuidString: sourceMessageIDString),
              let sourceRoleRaw = quote["sourceRole"] as? String,
              let sourceRole = MessageRole(rawValue: sourceRoleRaw),
              let quotedText = quote["quotedText"] as? String else {
            return nil
        }

        let sourceThreadID: UUID?
        if let rawThreadID = quote["sourceThreadID"] as? String {
            sourceThreadID = UUID(uuidString: rawThreadID)
        } else {
            sourceThreadID = nil
        }

        let createdAt = decodeDate(quote["createdAt"]) ?? .distantPast
        return .quote(
            QuoteContent(
                sourceMessageID: sourceMessageID,
                sourceThreadID: sourceThreadID,
                sourceRole: sourceRole,
                sourceModelName: quote["sourceModelName"] as? String,
                quotedText: quotedText,
                prefixContext: quote["prefixContext"] as? String,
                suffixContext: quote["suffixContext"] as? String,
                createdAt: createdAt
            )
        )
    }

    private static func decodeImage(
        _ rawPart: [String: Any],
        deferredSource: DeferredMessagePartReference
    ) -> RenderedContentPart? {
        guard let image = rawPart["image"] as? [String: Any],
              let mimeType = image["mimeType"] as? String else { return nil }
        let url = url(from: image["url"])
        let hasInlineData = image.keys.contains("data") && !(image["data"] is NSNull)

        return .image(
            RenderedImageContent(
                mimeType: mimeType,
                inlineData: nil,
                url: url,
                assetDisposition: mediaAssetDisposition(
                    rawValue: image["assetDisposition"] as? String,
                    url: url,
                    hasInlineData: hasInlineData
                ),
                deferredSource: hasInlineData ? deferredSource : nil
            )
        )
    }

    private static func decodeVideo(_ rawPart: [String: Any]) -> RenderedContentPart? {
        guard let video = rawPart["video"] as? [String: Any],
              let mimeType = video["mimeType"] as? String else { return nil }
        let url = url(from: video["url"])
        let hasInlineData = video.keys.contains("data") && !(video["data"] is NSNull)

        return .video(
            VideoContent(
                mimeType: mimeType,
                data: nil,
                url: url,
                assetDisposition: mediaAssetDisposition(
                    rawValue: video["assetDisposition"] as? String,
                    url: url,
                    hasInlineData: hasInlineData
                )
            )
        )
    }

    private static func decodeFile(
        _ rawPart: [String: Any],
        deferredSource: DeferredMessagePartReference
    ) -> RenderedContentPart? {
        guard let file = rawPart["file"] as? [String: Any],
              let mimeType = file["mimeType"] as? String,
              let filename = file["filename"] as? String else { return nil }
        let extractedText = file["extractedText"] as? String
        let hasDeferredExtractedText = file.keys.contains("extractedText") && !(file["extractedText"] is NSNull)

        return .file(
            RenderedFileContent(
                mimeType: mimeType,
                filename: filename,
                url: url(from: file["url"]),
                extractedText: extractedText,
                hasDeferredExtractedText: extractedText == nil && hasDeferredExtractedText,
                deferredSource: extractedText == nil && hasDeferredExtractedText ? deferredSource : nil
            )
        )
    }

    private static func decodeAudio(_ rawPart: [String: Any]) -> RenderedContentPart? {
        guard let audio = rawPart["audio"] as? [String: Any],
              let mimeType = audio["mimeType"] as? String else { return nil }

        return .audio(
            AudioContent(
                mimeType: mimeType,
                data: nil,
                url: url(from: audio["url"])
            )
        )
    }

    private static func decodeThinking(_ rawPart: [String: Any]) -> RenderedContentPart? {
        guard let text = rawPart["thinking"] as? String else { return nil }

        return .thinking(
            ThinkingBlock(
                text: text,
                signature: rawPart["signature"] as? String,
                provider: rawPart["provider"] as? String
            )
        )
    }

    private static func decodeRedactedThinking(_ rawPart: [String: Any]) -> RenderedContentPart? {
        guard let data = rawPart["redactedData"] as? String else { return nil }

        return .redactedThinking(
            RedactedThinkingBlock(
                data: data,
                provider: rawPart["provider"] as? String
            )
        )
    }

    private static func url(from value: Any?) -> URL? {
        guard let string = value as? String else { return nil }
        return URL(string: string)
    }

    private static func decodeDate(_ value: Any?) -> Date? {
        if let timeInterval = value as? TimeInterval {
            return Date(timeIntervalSinceReferenceDate: timeInterval)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSinceReferenceDate: number.doubleValue)
        }
        if let string = value as? String,
           let timeInterval = TimeInterval(string) {
            return Date(timeIntervalSinceReferenceDate: timeInterval)
        }
        return nil
    }

    private static func mediaAssetDisposition(
        rawValue: String?,
        url: URL?,
        hasInlineData: Bool
    ) -> MediaAssetDisposition {
        if let rawValue,
           let disposition = MediaAssetDisposition(rawValue: rawValue) {
            return disposition
        }

        if hasInlineData || url?.isFileURL == true {
            return .managed
        }

        return url == nil ? .managed : .externalReference
    }
}
