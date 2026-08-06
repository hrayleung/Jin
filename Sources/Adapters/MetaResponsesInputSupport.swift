import Foundation

enum MetaResponsesInputSupport {
    static func textContentPart(_ text: String, role: MessageRole) -> [String: Any] {
        [
            "type": role == .assistant ? "output_text" : "input_text",
            "text": text
        ]
    }

    static func imageContentPart(imageURL: String) -> [String: Any] {
        [
            "type": "input_image",
            "image_url": imageURL
        ]
    }

    static func imageContentPart(fileID: String) -> [String: Any] {
        [
            "type": "input_image",
            "file_id": fileID
        ]
    }

    static func inlineFileContentPart(filename: String, mimeType: String, data: Data) -> [String: Any] {
        [
            "type": "input_file",
            "filename": filename,
            "file_data": mediaDataURI(mimeType: mimeType, data: data)
        ]
    }

    static func remoteFileContentPart(url: URL) -> [String: Any] {
        [
            "type": "input_file",
            "file_url": url.absoluteString
        ]
    }

    static func hostedFileContentPart(fileID: String, filename: String?) -> [String: Any] {
        var part: [String: Any] = [
            "type": "input_file",
            "file_id": fileID
        ]
        if let filename, !filename.isEmpty {
            part["filename"] = filename
        }
        return part
    }

    static func videoContentPart(videoURL: String) -> [String: Any] {
        [
            "type": "input_video",
            "video_url": videoURL
        ]
    }

    static func videoContentPart(fileID: String) -> [String: Any] {
        [
            "type": "input_video",
            "file_id": fileID
        ]
    }

    static func fallbackFileContentPart(file: FileContent, role: MessageRole) -> [String: Any] {
        textContentPart(AttachmentPromptRenderer.fallbackText(for: file), role: role)
    }

    /// Stateless Meta reasoning replay item.
    ///
    /// Docs (dev.meta.ai Responses → reasoning items):
    /// - `encrypted_content` is required for replay without server storage
    /// - `summary` is required on input (use `[]` when none)
    /// - `id` is optional when encrypted_content is present
    /// - Must be followed by an assistant message or `function_call` before the next
    ///   user/system/developer message
    static func reasoningReplayItem(encryptedContent: String, id: String?) -> [String: Any] {
        var item: [String: Any] = [
            "type": "reasoning",
            "encrypted_content": encryptedContent,
            "summary": [[String: Any]]()
        ]
        if let id, !id.isEmpty {
            item["id"] = id
        }
        return item
    }

    /// Minimal assistant turn used when a reasoning-only response must be followed by
    /// something before the next user message (Meta conversation structure rules).
    static func emptyAssistantMessageItem() -> [String: Any] {
        [
            "role": "assistant",
            "content": [
                [
                    "type": "output_text",
                    "text": ""
                ]
            ]
        ]
    }

    static func functionCallItem(_ call: ToolCall) -> [String: Any] {
        [
            "type": "function_call",
            "call_id": call.id,
            "name": call.name,
            "arguments": encodeJSONObject(call.arguments)
        ]
    }

    static func functionCallOutputItem(_ result: ToolResult) -> [String: Any] {
        [
            "type": "function_call_output",
            "call_id": result.toolCallID,
            "output": sanitizedToolOutput(result.content, toolName: result.toolName)
        ]
    }

    static func responsesToolDefinition(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "name": tool.name,
            "description": tool.description,
            "parameters": toolParametersSchema(tool.parameters)
        ]
    }

    static func sanitizedToolOutput(_ raw: String, toolName: String?) -> String {
        if let trimmed = raw.trimmedNonEmpty { return trimmed }
        if let toolName, !toolName.isEmpty {
            return "Tool \(toolName) returned no output"
        }
        return "Tool returned no output"
    }

    static func isPDF(_ mimeType: String) -> Bool {
        normalizedMIMEType(mimeType) == "application/pdf"
    }

    static func isSupportedAudioMIME(_ mimeType: String) -> Bool {
        let mime = normalizedMIMEType(mimeType)
        return mime == "audio/mpeg" || mime == "audio/mp3" || mime == "audio/wav" || mime == "audio/x-wav"
    }

    static func isSupportedVideoMIME(_ mimeType: String) -> Bool {
        normalizedMIMEType(mimeType) == "video/mp4"
            || normalizedMIMEType(mimeType).hasPrefix("video/")
    }
}
