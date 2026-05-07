import Foundation

// MARK: - OpenAI Responses API Message & Content Translation

extension OpenAIAdapter {

    func translateInput(
        _ messages: [Message],
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) async throws -> [[String: Any]] {
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
                if let translated = try await translateMessage(
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

    private func translateMessage(
        _ message: Message,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) async throws -> [String: Any]? {
        var content: [[String: Any]] = []
        for part in message.content {
            if let translated = try await translateContentPart(
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

    private func translateFunctionCalls(_ calls: [ToolCall]) -> [[String: Any]] {
        calls.map(OpenAIResponsesInputSupport.functionCallItem)
    }

    private func translateContentPart(
        _ part: ContentPart,
        role: MessageRole,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) async throws -> [String: Any]? {
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

                if let hostedFile = try await uploadHostedOpenAIFile(file) {
                    return OpenAIResponsesInputSupport.hostedFileContentPart(fileID: hostedFile.id)
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

    private func uploadHostedOpenAIFile(_ file: FileContent) async throws -> HostedProviderFileReference? {
        do {
            return try await ProviderHostedFileStore.shared.uploadOpenAIFile(
                file: file,
                baseURL: baseURL,
                apiKey: apiKey,
                networkManager: networkManager
            )
        } catch {
            if shouldFallbackFromHostedFileUpload(error) {
                return nil
            }
            throw error
        }
    }

    func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        OpenAIResponsesInputSupport.responsesToolDefinition(tool)
    }
}
