import XCTest
@testable import Jin

final class MarkdownTemplateExportsTests: XCTestCase {
    func testTemplateReferencesRendererRuntimeAndCoreRuntime() throws {
        guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html") else {
            XCTFail("Missing markdown-template.html in Jin resource bundle")
            return
        }

        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.contains("markdown-core-runtime.js"), "Expected markdown-it core runtime in markdown template")
        XCTAssertTrue(html.contains("markdown-render-runtime.js"), "Expected renderer runtime in markdown template")
    }

    func testRendererRuntimeExportsTextUpdateFunctions() throws {
        let runtime = try rendererRuntimeSource()

        XCTAssertTrue(runtime.contains("window.updateWithText"), "Expected updateWithText export in markdown runtime")
        XCTAssertTrue(runtime.contains("window.updateStreamingWithText"), "Expected updateStreamingWithText export in markdown runtime")
        XCTAssertTrue(runtime.contains("markdown-prism-runtime.js"), "Expected Prism runtime in markdown runtime")
        XCTAssertFalse(runtime.contains("markdown-hljs-runtime.js"), "Did not expect legacy highlight.js runtime in markdown runtime")
    }

    func testRendererRuntimeKeepsMarkdownParserPolicyStable() throws {
        let runtime = try rendererRuntimeSource()

        XCTAssertTrue(runtime.contains("html: false"), "Expected raw HTML to stay disabled")
        XCTAssertTrue(runtime.contains("linkify: true"), "Expected linkify to stay enabled")
        XCTAssertTrue(runtime.contains("typographer: false"), "Expected typographer to stay disabled")
        XCTAssertFalse(runtime.contains("preferHardBreaks"), "Renderer should not use hard-break preference as markdown repair")
        XCTAssertFalse(runtime.contains("options.breaks"), "Renderer should not dynamically toggle markdown-it breaks")
    }

    func testRendererRuntimeExportsSelectionAndHighlightBridge() throws {
        let runtime = try rendererRuntimeSource()

        XCTAssertTrue(runtime.contains("window.setSelectionContext"), "Expected selection context export in markdown runtime")
        XCTAssertTrue(runtime.contains("window.setPersistedHighlights"), "Expected persisted highlight export in markdown runtime")
        XCTAssertTrue(runtime.contains("messageHandlers.selectionChanged"), "Expected WKScriptMessage bridge for selection changes")
        XCTAssertTrue(runtime.contains("mark[data-jin-highlight-id]"), "Expected persisted highlight styling selectors in markdown runtime")
        XCTAssertTrue(runtime.contains("resolveHighlightOffsets"), "Expected persisted highlights to remap offsets against rendered text")
        XCTAssertTrue(runtime.contains("function selectableTextContent"), "Expected highlights and selection snapshots to share selectable-text coordinates")
    }

    func testTemplateStylesPersistedHighlights() throws {
        guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html") else {
            XCTFail("Missing markdown-template.html in Jin resource bundle")
            return
        }

        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.contains("mark[data-jin-highlight-id]"), "Expected persisted highlight styling in markdown template")
    }

    func testRendererRuntimeReferencesPrismRuntime() throws {
        let runtime = try rendererRuntimeSource()

        XCTAssertTrue(runtime.contains("markdown-prism-runtime.js"), "Expected Prism runtime in markdown runtime")
        XCTAssertFalse(runtime.contains("markdown-hljs-runtime.js"), "Did not expect legacy highlight.js runtime in markdown runtime")
    }

    func testTemplateIncludesReversibleCodeBlockHeightFolding() throws {
        let runtime = try rendererRuntimeSource()

        XCTAssertTrue(runtime.contains("function updateCodeHeightCollapseUI"), "Expected code block height folding UI helper")
        XCTAssertTrue(runtime.contains("function setCodeHeightCollapsed"), "Expected reversible code block height folding state helper")
        XCTAssertTrue(runtime.contains("more lines"), "Expected expand bar with line count")
        XCTAssertTrue(runtime.contains("previewAutoExpanded"), "Expected preview mode to preserve height folding state")
        XCTAssertTrue(runtime.contains("showLineNumbers"), "Expected merged code block line-number setting support")
        XCTAssertTrue(runtime.contains("collapseLineThreshold"), "Expected collapse line threshold setting support")
        XCTAssertTrue(runtime.contains("toggleCodeHeightFold"), "Expected header fold button to control height collapse")
    }

    func testRendererRuntimeMapsConfCodeBlocksToConfigLogo() throws {
        let runtime = try rendererRuntimeSource()

        XCTAssertTrue(runtime.contains("conf: 'ini'"), "Expected conf language alias to reuse ini logo")
        XCTAssertTrue(runtime.contains("file-settings-outline"), "Expected config-style fallback icon URL in markdown runtime")
    }

    func testRendererRuntimeMapsTmuxCodeBlocksToTmuxLogo() throws {
        let runtime = try rendererRuntimeSource()

        XCTAssertTrue(runtime.contains("tmux-original.svg"), "Expected tmux code blocks to use the tmux logo")
    }

    private func rendererRuntimeSource() throws -> String {
        guard let url = Bundle.module.url(forResource: "markdown-render-runtime", withExtension: "js") else {
            XCTFail("Missing markdown-render-runtime.js in Jin resource bundle")
            return ""
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}
