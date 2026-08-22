import Foundation

enum OpenAIResponsesInputSupport {
    static func textContentPart(_ text: String, role: MessageRole) -> [String: Any] {
        [
            "type": textContentType(for: role),
            "text": text
        ]
    }

    static func textContentType(for role: MessageRole) -> String {
        role == .assistant ? "output_text" : "input_text"
    }

    static func imageContentPart(imageURL: String) -> [String: Any] {
        [
            "type": "input_image",
            "image_url": imageURL
        ]
    }

    static func remoteFileContentPart(url: URL) -> [String: Any] {
        [
            "type": "input_file",
            "file_url": url.absoluteString
        ]
    }

    static func hostedFileContentPart(fileID: String) -> [String: Any] {
        [
            "type": "input_file",
            "file_id": fileID
        ]
    }

    static func inlineFileContentPart(file: FileContent, mimeType: String, data: Data) -> [String: Any] {
        [
            "type": "input_file",
            "filename": file.filename,
            "file_data": mediaDataURI(mimeType: mimeType, data: data)
        ]
    }

    static func fallbackFileContentPart(file: FileContent, role: MessageRole) -> [String: Any] {
        textContentPart(AttachmentPromptRenderer.fallbackText(for: file), role: role)
    }

    /// `providerName` is not always "OpenAI": `OpenAIAdapter` is also the `/responses`
    /// delegate for OpenCode Go (gpt-5.6-luna) and Ramp Router, and naming the wrong
    /// vendor in a notice the model reads back is needlessly confusing.
    static func unsupportedVideoContentPart(
        video: VideoContent,
        role: MessageRole,
        providerName: String = "OpenAI"
    ) -> [String: Any] {
        textContentPart(
            unsupportedVideoInputNotice(video, providerName: providerName, apiName: "Responses API"),
            role: role
        )
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

    static func shouldAllowNativeFileInput(
        mimeType: String,
        supportsNativeFileInput: Bool,
        allowNativePDF: Bool
    ) -> Bool {
        supportsNativeFileInput
            && openAISupportedFileMIMETypes.contains(mimeType)
            && (mimeType != "application/pdf" || allowNativePDF)
    }
}
