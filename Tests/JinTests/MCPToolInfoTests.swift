import XCTest
@testable import Jin

final class MCPToolInfoTests: XCTestCase {
    func testModelFacingDescriptionUsesTitleWhenDescriptionIsEmpty() {
        let tool = MCPToolInfo(
            name: "search",
            description: "",
            inputSchema: ParameterSchema(properties: [:]),
            title: "Web Search"
        )

        XCTAssertEqual(tool.modelFacingDescription, "Web Search")
    }

    func testModelFacingDescriptionDoesNotRepeatTitlePrefix() {
        let tool = MCPToolInfo(
            name: "search",
            description: "Web Search finds pages.",
            inputSchema: ParameterSchema(properties: [:]),
            title: "Web Search"
        )

        XCTAssertEqual(tool.modelFacingDescription, "Web Search finds pages.")
    }

    func testModelFacingDescriptionCollapsesWhitespaceAndCapsLength() {
        let longTail = String(repeating: "word ", count: 200)
        let tool = MCPToolInfo(
            name: "search",
            description: "Line one.\n\n\(longTail)",
            inputSchema: ParameterSchema(properties: [:])
        )

        let description = tool.modelFacingDescription
        XCTAssertFalse(description.contains("\n"))
        XCTAssertLessThanOrEqual(description.count, MCPToolInfo.maxModelFacingDescriptionLength)
        XCTAssertTrue(description.hasSuffix("…"))
        XCTAssertTrue(description.hasPrefix("Line one."))
    }
}
