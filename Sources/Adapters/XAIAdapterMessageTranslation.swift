import Foundation

// MARK: - Input / Message Translation

extension XAIAdapter {
    func translateInput(_ messages: [Message], supportsNativePDF: Bool) throws -> [[String: Any]] {
        var items: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .tool:
                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append(XAIResponsesInputSupport.functionCallOutputItem(result))
                    }
                }

            case .system, .user, .assistant:
                if let translated = try translateMessage(message, supportsNativePDF: supportsNativePDF) {
                    items.append(translated)
                }

                if message.role == .assistant, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    items.append(contentsOf: translateFunctionCalls(toolCalls))
                }

                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append(XAIResponsesInputSupport.functionCallOutputItem(result))
                    }
                }
            }
        }

        return items
    }

    private func translateMessage(_ message: Message, supportsNativePDF: Bool) throws -> [String: Any]? {
        var content: [[String: Any]] = []
        for part in message.content {
            if let translated = try translateContentPart(part, supportsNativePDF: supportsNativePDF) {
                content.append(translated)
            }
        }

        guard !content.isEmpty else { return nil }

        return [
            "role": message.role.rawValue,
            "content": content
        ]
    }

    private func translateFunctionCalls(_ calls: [ToolCall]) -> [[String: Any]] {
        calls.map(XAIResponsesInputSupport.functionCallItem)
    }

    private func translateContentPart(_ part: ContentPart, supportsNativePDF: Bool) throws -> [String: Any]? {
        switch part {
        case .text(let text):
            return XAIResponsesInputSupport.textContentPart(text)
        case .quote(let quote):
            return XAIResponsesInputSupport.textContentPart(quote.quotedText)

        case .image(let image):
            if let data = image.data {
                return XAIResponsesInputSupport.imageContentPart(
                    imageURL: mediaDataURI(mimeType: image.mimeType, data: data)
                )
            }
            if let url = image.url {
                if url.isFileURL {
                    let data = try resolveFileData(from: url)
                    return XAIResponsesInputSupport.imageContentPart(
                        imageURL: mediaDataURI(mimeType: image.mimeType, data: data)
                    )
                }
                return XAIResponsesInputSupport.imageContentPart(imageURL: url.absoluteString)
            }
            return nil

        case .file(let file):
            if XAIResponsesInputSupport.canInlinePDF(file, supportsNativePDF: supportsNativePDF) {
                let pdfData: Data?
                if let data = file.data {
                    pdfData = data
                } else if let url = file.url, url.isFileURL {
                    pdfData = try resolveFileData(from: url)
                } else {
                    pdfData = nil
                }

                if let pdfData {
                    return XAIResponsesInputSupport.inlinePDFContentPart(file: file, data: pdfData)
                }
            }

            return XAIResponsesInputSupport.fallbackFileContentPart(file: file)

        case .video(let video):
            return XAIResponsesInputSupport.unsupportedVideoContentPart(video: video)

        case .thinking, .redactedThinking, .audio:
            return nil
        }
    }

    func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        XAIResponsesInputSupport.responsesToolDefinition(tool)
    }
}
