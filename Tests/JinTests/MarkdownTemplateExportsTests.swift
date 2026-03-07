import XCTest
@testable import Jin

final class MarkdownTemplateExportsTests: XCTestCase {
    func testTemplateExportsTextUpdateFunctions() throws {
        guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html") else {
            XCTFail("Missing markdown-template.html in Jin resource bundle")
            return
        }

        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.contains("window.updateWithText"), "Expected updateWithText export in markdown template")
        XCTAssertTrue(html.contains("window.updateStreamingWithText"), "Expected updateStreamingWithText export in markdown template")
        XCTAssertTrue(html.contains("markdown-prism-runtime.js"), "Expected Prism runtime in markdown template")
        XCTAssertFalse(html.contains("markdown-hljs-runtime.js"), "Did not expect legacy highlight.js runtime in markdown template")
    }
}
