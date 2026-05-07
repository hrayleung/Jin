import XCTest
@testable import Jin

final class OpenAIResponsesInputSupportTests: XCTestCase {
    func testTextContentPartUsesInputTextExceptAssistantOutputText() {
        XCTAssertEqual(
            OpenAIResponsesInputSupport.textContentPart("hello", role: .user)["type"] as? String,
            "input_text"
        )
        XCTAssertEqual(
            OpenAIResponsesInputSupport.textContentPart("hello", role: .system)["type"] as? String,
            "input_text"
        )
        XCTAssertEqual(
            OpenAIResponsesInputSupport.textContentPart("hello", role: .assistant)["type"] as? String,
            "output_text"
        )
    }

    func testFilePartsBuildRemoteHostedInlineAndFallbackShapes() throws {
        let remoteURL = URL(string: "https://cdn.example.com/notes.pdf")!
        let remote = OpenAIResponsesInputSupport.remoteFileContentPart(url: remoteURL)
        XCTAssertEqual(remote["type"] as? String, "input_file")
        XCTAssertEqual(remote["file_url"] as? String, remoteURL.absoluteString)

        let hosted = OpenAIResponsesInputSupport.hostedFileContentPart(fileID: "file_123")
        XCTAssertEqual(hosted["type"] as? String, "input_file")
        XCTAssertEqual(hosted["file_id"] as? String, "file_123")

        let file = FileContent(
            mimeType: "text/markdown",
            filename: "notes.md",
            data: Data("# Notes".utf8),
            extractedText: "# Notes"
        )
        let inline = OpenAIResponsesInputSupport.inlineFileContentPart(
            file: file,
            mimeType: "text/markdown",
            data: Data("# Notes".utf8)
        )
        XCTAssertEqual(inline["type"] as? String, "input_file")
        XCTAssertEqual(inline["filename"] as? String, "notes.md")
        XCTAssertEqual(inline["file_data"] as? String, "data:text/markdown;base64,\(Data("# Notes".utf8).base64EncodedString())")

        let fallback = OpenAIResponsesInputSupport.fallbackFileContentPart(file: file, role: .assistant)
        XCTAssertEqual(fallback["type"] as? String, "output_text")
        XCTAssertEqual(fallback["text"] as? String, AttachmentPromptRenderer.fallbackText(for: file))
    }

    func testFunctionItemsAndToolDefinitionsPreserveResponsesShapes() throws {
        let toolResult = ToolResult(toolCallID: "call_1", toolName: "lookup", content: " \n ")
        let output = OpenAIResponsesInputSupport.functionCallOutputItem(toolResult)
        XCTAssertEqual(output["type"] as? String, "function_call_output")
        XCTAssertEqual(output["call_id"] as? String, "call_1")
        XCTAssertEqual(output["output"] as? String, "Tool lookup returned no output")

        let call = ToolCall(id: "call_1", name: "lookup", arguments: ["query": AnyCodable("weather")])
        let callItem = OpenAIResponsesInputSupport.functionCallItem(call)
        XCTAssertEqual(callItem["type"] as? String, "function_call")
        XCTAssertEqual(callItem["call_id"] as? String, "call_1")
        XCTAssertEqual(callItem["name"] as? String, "lookup")
        XCTAssertEqual(callItem["arguments"] as? String, "{\"query\":\"weather\"}")

        let tool = ToolDefinition(
            id: "tool_1",
            name: "lookup",
            description: "Lookup a value",
            parameters: ParameterSchema(
                properties: [
                    "query": PropertySchema(type: "string", description: "Search query")
                ],
                required: ["query"]
            ),
            source: .builtin
        )
        let definition = OpenAIResponsesInputSupport.responsesToolDefinition(tool)
        XCTAssertEqual(definition["type"] as? String, "function")
        XCTAssertEqual(definition["name"] as? String, "lookup")
        XCTAssertEqual(definition["description"] as? String, "Lookup a value")

        let parameters = try XCTUnwrap(definition["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["required"] as? [String], ["query"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let query = try XCTUnwrap(properties["query"] as? [String: Any])
        XCTAssertEqual(query["type"] as? String, "string")
        XCTAssertEqual(query["description"] as? String, "Search query")
    }

    func testSanitizedToolOutputTrimsAndUsesGenericFallbackWithoutToolName() {
        XCTAssertEqual(
            OpenAIResponsesInputSupport.sanitizedToolOutput("  useful output\n", toolName: "lookup"),
            "useful output"
        )
        XCTAssertEqual(
            OpenAIResponsesInputSupport.sanitizedToolOutput("\n", toolName: nil),
            "Tool returned no output"
        )
    }

    func testShouldAllowNativeFileInputRequiresSupportAndPDFPermission() {
        XCTAssertTrue(
            OpenAIResponsesInputSupport.shouldAllowNativeFileInput(
                mimeType: "text/markdown",
                supportsNativeFileInput: true,
                allowNativePDF: false
            )
        )
        XCTAssertTrue(
            OpenAIResponsesInputSupport.shouldAllowNativeFileInput(
                mimeType: "application/pdf",
                supportsNativeFileInput: true,
                allowNativePDF: true
            )
        )
        XCTAssertFalse(
            OpenAIResponsesInputSupport.shouldAllowNativeFileInput(
                mimeType: "application/pdf",
                supportsNativeFileInput: true,
                allowNativePDF: false
            )
        )
        XCTAssertFalse(
            OpenAIResponsesInputSupport.shouldAllowNativeFileInput(
                mimeType: "text/markdown",
                supportsNativeFileInput: false,
                allowNativePDF: true
            )
        )
        XCTAssertFalse(
            OpenAIResponsesInputSupport.shouldAllowNativeFileInput(
                mimeType: "application/octet-stream",
                supportsNativeFileInput: true,
                allowNativePDF: true
            )
        )
    }

    func testUnsupportedVideoContentPartUsesRoleSpecificTextType() {
        let video = VideoContent(mimeType: "video/mp4", data: Data("MP4".utf8), url: nil)

        let userPart = OpenAIResponsesInputSupport.unsupportedVideoContentPart(video: video, role: .user)
        XCTAssertEqual(userPart["type"] as? String, "input_text")
        XCTAssertTrue((userPart["text"] as? String)?.contains("OpenAI") == true)

        let assistantPart = OpenAIResponsesInputSupport.unsupportedVideoContentPart(video: video, role: .assistant)
        XCTAssertEqual(assistantPart["type"] as? String, "output_text")
    }
}
