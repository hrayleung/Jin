import Foundation

extension OpenAIWebSocketAdapter {

    // MARK: - Input Translation

    func translateInput(
        _ messages: [Message],
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) throws -> [[String: Any]] {
        var items: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .tool:
                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append(OpenAIResponsesInputSupport.functionCallOutputItem(result))
                    }
                }

            case .system, .user, .assistant:
                if let translated = try translateMessage(
                    message,
                    supportsNativeFileInput: supportsNativeFileInput,
                    allowNativePDF: allowNativePDF
                ) {
                    items.append(translated)
                }

                if message.role == .assistant, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    items.append(contentsOf: translateFunctionCalls(toolCalls))
                }

                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append(OpenAIResponsesInputSupport.functionCallOutputItem(result))
                    }
                }
            }
        }

        return items
    }

    func translateMessage(
        _ message: Message,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) throws -> [String: Any]? {
        var content: [[String: Any]] = []
        for part in message.content {
            if let translated = try translateContentPart(
                part,
                role: message.role,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            ) {
                content.append(translated)
            }
        }

        guard !content.isEmpty else { return nil }

        return [
            "role": message.role.rawValue,
            "content": content
        ]
    }

    func translateFunctionCalls(_ calls: [ToolCall]) -> [[String: Any]] {
        calls.map(OpenAIResponsesInputSupport.functionCallItem)
    }

    func translateContentPart(
        _ part: ContentPart,
        role: MessageRole,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) throws -> [String: Any]? {
        switch part {
        case .text(let text):
            return OpenAIResponsesInputSupport.textContentPart(text, role: role)
        case .quote(let quote):
            return OpenAIResponsesInputSupport.textContentPart(quote.quotedText, role: role)

        case .image(let image):
            if let data = image.data {
                return OpenAIResponsesInputSupport.imageContentPart(
                    imageURL: mediaDataURI(mimeType: image.mimeType, data: data)
                )
            }
            if let url = image.url {
                if url.isFileURL {
                    let data = try resolveFileData(from: url)
                    return OpenAIResponsesInputSupport.imageContentPart(
                        imageURL: mediaDataURI(mimeType: image.mimeType, data: data)
                    )
                }
                return OpenAIResponsesInputSupport.imageContentPart(imageURL: url.absoluteString)
            }
            return nil

        case .file(let file):
            let normalizedFileMIMEType = normalizedMIMEType(file.mimeType)
            let shouldAllowNativeFileUpload = OpenAIResponsesInputSupport.shouldAllowNativeFileInput(
                mimeType: normalizedFileMIMEType,
                supportsNativeFileInput: supportsNativeFileInput,
                allowNativePDF: allowNativePDF
            )

            if shouldAllowNativeFileUpload {
                // Remote URL: use file_url directly (Responses API supports this)
                if let url = file.url, !url.isFileURL {
                    return OpenAIResponsesInputSupport.remoteFileContentPart(url: url)
                }

                // Load data from file URL or use existing data
                let fileData: Data?
                if let data = file.data {
                    fileData = data
                } else if let url = file.url, url.isFileURL {
                    fileData = try resolveFileData(from: url)
                } else {
                    fileData = nil
                }

                if let fileData {
                    return OpenAIResponsesInputSupport.inlineFileContentPart(
                        file: file,
                        mimeType: normalizedFileMIMEType,
                        data: fileData
                    )
                }
            }

            // Fallback to text extraction for unsupported types or models
            return OpenAIResponsesInputSupport.fallbackFileContentPart(file: file, role: role)

        case .video(let video):
            return OpenAIResponsesInputSupport.unsupportedVideoContentPart(video: video, role: role)

        case .audio(let audio):
            guard role == .user else { return nil }
            return try openAIInputAudioPart(audio)

        case .thinking, .redactedThinking:
            return nil
        }
    }

    func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        OpenAIResponsesInputSupport.responsesToolDefinition(tool)
    }

}
