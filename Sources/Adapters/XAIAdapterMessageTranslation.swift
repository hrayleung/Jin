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
                        items.append([
                            "type": "function_call_output",
                            "call_id": result.toolCallID,
                            "output": sanitizedToolOutput(result.content, toolName: result.toolName)
                        ])
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

    private func translateContentPart(_ part: ContentPart, supportsNativePDF: Bool) throws -> [String: Any]? {
        switch part {
        case .text(let text):
            return [
                "type": "input_text",
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
            if supportsNativePDF && file.mimeType == "application/pdf" {
                let pdfData: Data?
                if let data = file.data {
                    pdfData = data
                } else if let url = file.url, url.isFileURL {
                    pdfData = try resolveFileData(from: url)
                } else {
                    pdfData = nil
                }

                if let pdfData {
                    return [
                        "type": "input_file",
                        "filename": file.filename,
                        "file_data": "data:application/pdf;base64,\(pdfData.base64EncodedString())"
                    ]
                }
            }

            let text = AttachmentPromptRenderer.fallbackText(for: file)
            return [
                "type": "input_text",
                "text": text
            ]

        case .video(let video):
            return [
                "type": "input_text",
                "text": unsupportedVideoInputNotice(video, providerName: "xAI")
            ]

        case .thinking, .redactedThinking, .audio:
            return nil
        }
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
