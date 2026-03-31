import Foundation

enum VertexAIMessageTranslation {
    static func translateMessages(
        _ messages: [Message],
        supportsNativePDF: Bool
    ) throws -> [[String: Any]] {
        try messages
            .filter { $0.role != .system }
            .map { try translateMessage($0, supportsNativePDF: supportsNativePDF) }
    }

    static func translateMessage(
        _ message: Message,
        supportsNativePDF: Bool
    ) throws -> [String: Any] {
        let role = message.role == .assistant ? "model" : "user"
        var parts = try translatedContentParts(for: message, supportsNativePDF: supportsNativePDF)
        parts.append(contentsOf: translatedToolCallParts(for: message))
        parts.append(contentsOf: translatedToolResultParts(for: message))

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return ["role": role, "parts": parts]
    }

    private static func translatedContentParts(
        for message: Message,
        supportsNativePDF: Bool
    ) throws -> [[String: Any]] {
        guard message.role != .tool else { return [] }

        var parts: [[String: Any]] = []
        for part in message.content {
            if case .thinking(let thinking) = part, message.role == .assistant {
                var translated: [String: Any] = ["text": thinking.text, "thought": true]
                if let signature = thinking.signature {
                    translated["thoughtSignature"] = signature
                }
                parts.append(translated)
                continue
            }

            if let translated = try translateContentPart(part, supportsNativePDF: supportsNativePDF) {
                parts.append(translated)
            }
        }
        return parts
    }

    private static func translateContentPart(
        _ part: ContentPart,
        supportsNativePDF: Bool
    ) throws -> [String: Any]? {
        switch part {
        case .text(let text):
            return ["text": text]
        case .image(let image):
            return try GeminiModelConstants.inlineDataPart(
                mimeType: image.mimeType,
                data: image.data,
                url: image.url
            )
        case .video(let video):
            return try GeminiModelConstants.inlineDataPart(
                mimeType: video.mimeType,
                data: video.data,
                url: video.url
            )
        case .audio(let audio):
            return try GeminiModelConstants.inlineDataPart(
                mimeType: audio.mimeType,
                data: audio.data,
                url: audio.url
            )
        case .file(let file):
            return try translateFilePart(file, supportsNativePDF: supportsNativePDF)
        case .thinking, .redactedThinking:
            return nil
        }
    }

    private static func translateFilePart(
        _ file: FileContent,
        supportsNativePDF: Bool
    ) throws -> [String: Any] {
        if supportsNativePDF,
           file.mimeType == "application/pdf",
           let inline = try GeminiModelConstants.inlineDataPart(
                mimeType: "application/pdf",
                data: file.data,
                url: file.url
           ) {
            return inline
        }

        return ["text": googleFileFallbackText(file, providerName: "Vertex AI")]
    }

    private static func translatedToolCallParts(for message: Message) -> [[String: Any]] {
        guard message.role == .assistant, let toolCalls = message.toolCalls else { return [] }

        return toolCalls.map { call in
            var translated: [String: Any] = [
                "functionCall": [
                    "name": call.name,
                    "args": call.arguments.mapValues { $0.value }
                ]
            ]
            if let signature = call.signature {
                translated["thoughtSignature"] = signature
            }
            return translated
        }
    }

    private static func translatedToolResultParts(for message: Message) -> [[String: Any]] {
        guard message.role == .tool, let toolResults = message.toolResults else { return [] }

        return toolResults.compactMap { result in
            guard let toolName = result.toolName else { return nil }
            var translated: [String: Any] = [
                "functionResponse": [
                    "name": toolName,
                    "response": ["content": result.content]
                ]
            ]
            if let signature = result.signature {
                translated["thoughtSignature"] = signature
            }
            return translated
        }
    }
}
