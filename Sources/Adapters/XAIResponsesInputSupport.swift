import Foundation

enum XAIResponsesInputSupport {
    static func textContentPart(_ text: String) -> [String: Any] {
        [
            "type": "input_text",
            "text": text
        ]
    }

    static func imageContentPart(imageURL: String) -> [String: Any] {
        [
            "type": "input_image",
            "image_url": imageURL
        ]
    }

    static func inlinePDFContentPart(file: FileContent, data: Data) -> [String: Any] {
        [
            "type": "input_file",
            "filename": file.filename,
            "file_data": mediaDataURI(mimeType: "application/pdf", data: data)
        ]
    }

    static func fallbackFileContentPart(file: FileContent) -> [String: Any] {
        textContentPart(AttachmentPromptRenderer.fallbackText(for: file))
    }

    static func unsupportedVideoContentPart(video: VideoContent) -> [String: Any] {
        textContentPart(unsupportedVideoInputNotice(video, providerName: "xAI"))
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
            "parameters": [
                "type": tool.parameters.type,
                "properties": tool.parameters.properties.mapValues { $0.toDictionary() },
                "required": tool.parameters.required
            ]
        ]
    }

    static func sanitizedToolOutput(_ raw: String, toolName: String?) -> String {
        if let trimmed = raw.trimmedNonEmpty { return trimmed }

        if let toolName, !toolName.isEmpty {
            return "Tool \(toolName) returned no output"
        }
        return "Tool returned no output"
    }

    static func canInlinePDF(_ file: FileContent, supportsNativePDF: Bool) -> Bool {
        supportsNativePDF && file.mimeType == "application/pdf"
    }
}
