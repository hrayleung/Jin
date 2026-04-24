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

    func testTemplateExportsSelectionAndHighlightBridge() throws {
        guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html") else {
            XCTFail("Missing markdown-template.html in Jin resource bundle")
            return
        }

        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.contains("window.setSelectionContext"), "Expected selection context export in markdown template")
        XCTAssertTrue(html.contains("window.setPersistedHighlights"), "Expected persisted highlight export in markdown template")
        XCTAssertTrue(html.contains("messageHandlers.selectionChanged"), "Expected WKScriptMessage bridge for selection changes")
        XCTAssertTrue(html.contains("mark[data-jin-highlight-id]"), "Expected persisted highlight styling in markdown template")
        XCTAssertTrue(html.contains("resolveHighlightOffsets"), "Expected persisted highlights to remap offsets against rendered text")
        XCTAssertTrue(html.contains("preferHardBreaks"), "Expected markdown renderer options to carry hard-break preference")
    }

    func testTemplateIncludesReversibleCodeBlockHeightFolding() throws {
        guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html") else {
            XCTFail("Missing markdown-template.html in Jin resource bundle")
            return
        }

        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.contains("function updateCodeHeightCollapseUI"), "Expected code block height folding UI helper")
        XCTAssertTrue(html.contains("function setCodeHeightCollapsed"), "Expected reversible code block height folding state helper")
        XCTAssertTrue(html.contains("more lines"), "Expected expand bar with line count")
        XCTAssertTrue(html.contains("previewAutoExpanded"), "Expected preview mode to preserve height folding state")
        XCTAssertTrue(html.contains("showLineNumbers"), "Expected merged code block line-number setting support")
        XCTAssertTrue(html.contains("collapseLineThreshold"), "Expected collapse line threshold setting support")
        XCTAssertTrue(html.contains("toggleCodeHeightFold"), "Expected header fold button to control height collapse")
    }

    func testTemplateMapsConfCodeBlocksToConfigLogo() throws {
        guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html") else {
            XCTFail("Missing markdown-template.html in Jin resource bundle")
            return
        }

        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.contains("conf: 'ini'"), "Expected conf language alias to reuse ini logo")
        XCTAssertTrue(html.contains("file-settings-outline"), "Expected config-style fallback icon URL in markdown template")
    }

    func testTemplateMapsTmuxCodeBlocksToTmuxLogo() throws {
        guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html") else {
            XCTFail("Missing markdown-template.html in Jin resource bundle")
            return
        }

        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.contains("tmux-original.svg"), "Expected tmux code blocks to use the tmux logo")
    }
}
