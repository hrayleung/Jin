import XCTest
@testable import Jin

final class XAIResponsesInputSupportTests: XCTestCase {
    func testTextAndImagePartsUseXAIResponsesInputShapes() {
        let text = XAIResponsesInputSupport.textContentPart("hello")
        XCTAssertEqual(text["type"] as? String, "input_text")
        XCTAssertEqual(text["text"] as? String, "hello")

        let image = XAIResponsesInputSupport.imageContentPart(imageURL: "https://cdn.example.com/image.png")
        XCTAssertEqual(image["type"] as? String, "input_image")
        XCTAssertEqual(image["image_url"] as? String, "https://cdn.example.com/image.png")
    }

    func testPDFAndFallbackFilePartsUseExpectedShapes() throws {
        let pdfData = Data("%PDF".utf8)
        let pdf = FileContent(
            mimeType: "application/pdf",
            filename: "paper.pdf",
            data: pdfData,
            extractedText: nil
        )

        let inlinePDF = XAIResponsesInputSupport.inlinePDFContentPart(file: pdf, data: pdfData)
        XCTAssertEqual(inlinePDF["type"] as? String, "input_file")
        XCTAssertEqual(inlinePDF["filename"] as? String, "paper.pdf")
        XCTAssertEqual(inlinePDF["file_data"] as? String, "data:application/pdf;base64,\(pdfData.base64EncodedString())")

        let markdown = FileContent(
            mimeType: "text/markdown",
            filename: "notes.md",
            data: Data("# Notes".utf8),
            extractedText: "# Notes"
        )
        let fallback = XAIResponsesInputSupport.fallbackFileContentPart(file: markdown)
        XCTAssertEqual(fallback["type"] as? String, "input_text")
        XCTAssertEqual(fallback["text"] as? String, AttachmentPromptRenderer.fallbackText(for: markdown))
    }

    func testFunctionItemsAndToolDefinitionsPreserveResponsesShapes() throws {
        let result = ToolResult(toolCallID: "call_1", toolName: "lookup", content: " \n ")
        let output = XAIResponsesInputSupport.functionCallOutputItem(result)
        XCTAssertEqual(output["type"] as? String, "function_call_output")
        XCTAssertEqual(output["call_id"] as? String, "call_1")
        XCTAssertEqual(output["output"] as? String, "Tool lookup returned no output")

        let call = ToolCall(id: "call_1", name: "lookup", arguments: ["query": AnyCodable("weather")])
        let callItem = XAIResponsesInputSupport.functionCallItem(call)
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
        let definition = XAIResponsesInputSupport.responsesToolDefinition(tool)
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
            XAIResponsesInputSupport.sanitizedToolOutput("  useful output\n", toolName: "lookup"),
            "useful output"
        )
        XCTAssertEqual(
            XAIResponsesInputSupport.sanitizedToolOutput("\n", toolName: nil),
            "Tool returned no output"
        )
    }

    func testCanInlinePDFRequiresNativePDFSupportAndExactPDFMIMEType() {
        let pdf = FileContent(mimeType: "application/pdf", filename: "paper.pdf")
        let uppercasePDF = FileContent(mimeType: "Application/PDF", filename: "paper.pdf")
        let markdown = FileContent(mimeType: "text/markdown", filename: "notes.md")

        XCTAssertTrue(XAIResponsesInputSupport.canInlinePDF(pdf, supportsNativePDF: true))
        XCTAssertFalse(XAIResponsesInputSupport.canInlinePDF(pdf, supportsNativePDF: false))
        XCTAssertFalse(XAIResponsesInputSupport.canInlinePDF(uppercasePDF, supportsNativePDF: true))
        XCTAssertFalse(XAIResponsesInputSupport.canInlinePDF(markdown, supportsNativePDF: true))
    }

    func testUnsupportedVideoContentPartUsesXAIProviderNotice() {
        let video = VideoContent(mimeType: "video/mp4", data: Data("MP4".utf8), url: nil)
        let part = XAIResponsesInputSupport.unsupportedVideoContentPart(video: video)

        XCTAssertEqual(part["type"] as? String, "input_text")
        XCTAssertTrue((part["text"] as? String)?.contains("xAI") == true)
        XCTAssertTrue((part["text"] as? String)?.contains("video/mp4") == true)
    }
}
