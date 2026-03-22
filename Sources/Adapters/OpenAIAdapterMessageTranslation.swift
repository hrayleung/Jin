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
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": sanitizedToolOutput(result.content, toolName: result.toolName)
                        ])
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
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": sanitizedToolOutput(result.content, toolName: result.toolName)
                        ])
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
        calls.map { call in
            [
                "type": "function_call",
                "call_id": call.id,
                "name": call.name,
                "arguments": encodeJSONObject(call.arguments)
            ]
        }
    }

    private func sanitizedToolOutput(_ raw: String, toolName: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        if let toolName, !toolName.isEmpty {
            return "Tool \(toolName) returned no output"
        }
        return "Tool returned no output"
    }

    private func translateContentPart(
        _ part: ContentPart,
        role: MessageRole,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) async throws -> [String: Any]? {
        switch part {
        case .text(let text):
            // OpenAI Responses API: assistant uses output_text, others use input_text
            let textType = (role == .assistant) ? "output_text" : "input_text"
            return [
                "type": textType,
                "text": text
            ]

        case .image(let image):
            if let data = image.data {
                return [
                    "type": "input_image",
                    "image_url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"
                ]
            }
            if let url = image.url {
                if url.isFileURL {
                    let data = try resolveFileData(from: url)
                    return [
                        "type": "input_image",
                        "image_url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"
                    ]
                }
                return [
                    "type": "input_image",
                    "image_url": url.absoluteString
                ]
            }
            return nil

        case .file(let file):
            let normalizedFileMIMEType = normalizedMIMEType(file.mimeType)
            let shouldAllowNativeFileUpload =
                supportsNativeFileInput &&
                openAISupportedFileMIMETypes.contains(normalizedFileMIMEType) &&
                (normalizedFileMIMEType != "application/pdf" || allowNativePDF)

            if shouldAllowNativeFileUpload {
                // Remote URL: use file_url directly (Responses API supports this)
                if let url = file.url, !url.isFileURL {
                    return [
                        "type": "input_file",
                        "file_url": url.absoluteString
                    ]
                }

                if let hostedFile = try await uploadHostedOpenAIFile(file) {
                    return [
                        "type": "input_file",
                        "file_id": hostedFile.id
                    ]
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
                    return [
                        "type": "input_file",
                        "filename": file.filename,
                        "file_data": "data:\(normalizedFileMIMEType);base64,\(fileData.base64EncodedString())"
                    ]
                }
            }

            // Fallback to text extraction for unsupported types or models
            let textType = (role == .assistant) ? "output_text" : "input_text"
            let text = AttachmentPromptRenderer.fallbackText(for: file)
            return [
                "type": textType,
                "text": text
            ]

        case .video(let video):
            let textType = (role == .assistant) ? "output_text" : "input_text"
            return [
                "type": textType,
                "text": unsupportedVideoInputNotice(video, providerName: "OpenAI")
            ]

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

    private func openAIInputAudioPart(_ audio: AudioContent) throws -> [String: Any]? {
        let payloadData: Data?
        if let data = audio.data {
            payloadData = data
        } else if let url = audio.url, url.isFileURL {
            payloadData = try resolveFileData(from: url)
        } else {
            payloadData = nil
        }

        guard let payloadData, let format = openAIInputAudioFormat(mimeType: audio.mimeType) else {
            return nil
        }

        return [
            "type": "input_audio",
            "input_audio": [
                "data": payloadData.base64EncodedString(),
                "format": format
            ]
        ]
    }

    private func openAIInputAudioFormat(mimeType: String) -> String? {
        let lower = mimeType.lowercased()
        if lower == "audio/wav" || lower == "audio/x-wav" {
            return "wav"
        }
        if lower == "audio/mpeg" || lower == "audio/mp3" {
            return "mp3"
        }
        return nil
    }

    func translateSingleTool(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "name": tool.name,
            "description": tool.description,
            "parameters": [
                "type": tool.parameters.type,
                "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                "required": tool.parameters.required
            ]
        ]
    }
}
