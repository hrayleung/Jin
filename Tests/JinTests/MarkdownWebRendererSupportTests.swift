import CoreGraphics
import XCTest
@testable import Jin

final class MarkdownWebRendererSupportTests: XCTestCase {
    func testInlineRuntimeScriptsReplacesTemplateMarkers() {
        let template = """
        <html>
        <head>
        <!-- INLINE_CORE_RUNTIME -->
        <script src="markdown-core-runtime.js"></script>
        <script src="markdown-render-runtime.js"></script>
        </head>
        <body></body>
        </html>
        """

        let result = MarkdownWebRendererSupport.inlineRuntimeScripts(
            in: template,
            coreRuntimeJS: "window.coreReady = true;",
            renderRuntimeJS: "window.renderReady = true;"
        )

        XCTAssertTrue(result.didReplaceCoreRuntime)
        XCTAssertTrue(result.didReplaceRenderRuntime)
        XCTAssertFalse(result.html.contains("markdown-core-runtime.js"))
        XCTAssertFalse(result.html.contains("markdown-render-runtime.js"))
        XCTAssertTrue(result.html.contains("<script>\nwindow.coreReady = true;\n</script>"))
        XCTAssertTrue(result.html.contains("<script>\nwindow.renderReady = true;\n</script>"))
    }

    func testInlineRuntimeScriptsReportsMissingMarkersWithoutChangingHTML() {
        let template = "<html><body></body></html>"

        let result = MarkdownWebRendererSupport.inlineRuntimeScripts(
            in: template,
            coreRuntimeJS: "core",
            renderRuntimeJS: "render"
        )

        XCTAssertFalse(result.didReplaceCoreRuntime)
        XCTAssertFalse(result.didReplaceRenderRuntime)
        XCTAssertEqual(result.html, template)
    }

    func testEmbedMarkdownBootstrapInjectsBase64PayloadAndOptions() throws {
        let html = "<html><body><main></main></body></html>"
        let markdown = "Hello **Jin**"
        let base64 = try XCTUnwrap(markdown.data(using: .utf8)?.base64EncodedString())

        let result = MarkdownWebRendererSupport.embedMarkdownBootstrap(
            in: html,
            markdown: markdown,
            streaming: true,
            deferCodeHighlightUpgrade: true,
            codeBlockDisplayMode: "compact'quoted",
            codeBlockShowLineNumbers: true,
            codeBlockCollapseLineThreshold: 42
        )

        XCTAssertTrue(result.contains("<script>setCodeBlockDisplayMode('compact\\'quoted');"))
        XCTAssertTrue(result.contains("window.applyCodeBlockSettings({showLineNumbers:true,collapseLineThreshold:42});"))
        XCTAssertTrue(result.contains("updateStreamingContent('\(base64)',{deferCodeHighlightUpgrade:true});"))
        XCTAssertTrue(result.contains("</script>\n</body>"))
    }

    func testEmbedMarkdownBootstrapUsesUpdateContentForNonStreamingDefaultOptions() throws {
        let markdown = "plain"
        let base64 = try XCTUnwrap(markdown.data(using: .utf8)?.base64EncodedString())

        let result = MarkdownWebRendererSupport.embedMarkdownBootstrap(
            in: "<body></body>",
            markdown: markdown,
            streaming: false,
            deferCodeHighlightUpgrade: false
        )

        XCTAssertTrue(result.contains("updateContent('\(base64)',{});"))
        XCTAssertFalse(result.contains("deferCodeHighlightUpgrade:true"))
    }

    func testFontCSSAndJavaScriptHelpersPreserveExistingOutputShape() {
        XCTAssertEqual(
            MarkdownWebRendererSupport.resolvedBodyFontCSS(family: JinTypography.systemFontPreferenceValue),
            "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
        )
        XCTAssertEqual(
            MarkdownWebRendererSupport.resolvedCodeFontCSS(family: "Menlo"),
            "'Menlo', 'SF Mono', Menlo, monospace"
        )
        XCTAssertEqual(MarkdownWebRendererSupport.cssPixelValue(CGFloat(14.0)), "14")
        XCTAssertEqual(MarkdownWebRendererSupport.cssPixelValue(CGFloat(14.126)), "14.13")

        let js = MarkdownWebRendererSupport.fontUpdateJavaScript(
            bodyCSS: "body",
            codeCSS: "code",
            fontSizeCSS: "15.5"
        )
        XCTAssertEqual(
            js,
            "document.documentElement.style.setProperty('--body-font',\"body\");"
            + "document.documentElement.style.setProperty('--code-font',\"code\");"
            + "document.documentElement.style.setProperty('--body-font-size',\"15.5px\");"
        )
    }

    func testCoordinatorSupportClampsFiniteHeightsAndRejectsInvalidBodies() {
        XCTAssertNil(MarkdownWebRendererCoordinatorSupport.clampedHeight(from: "12"))
        XCTAssertNil(MarkdownWebRendererCoordinatorSupport.clampedHeight(from: CGFloat.nan))
        XCTAssertEqual(
            MarkdownWebRendererCoordinatorSupport.clampedHeight(from: CGFloat(0), maximumHeight: 10),
            CGFloat(1)
        )
        XCTAssertEqual(
            MarkdownWebRendererCoordinatorSupport.clampedHeight(from: CGFloat(5), maximumHeight: 10),
            CGFloat(5)
        )
        XCTAssertEqual(
            MarkdownWebRendererCoordinatorSupport.clampedHeight(from: CGFloat(40), maximumHeight: 10),
            CGFloat(10)
        )
    }

    func testCoordinatorSupportSelectionContextJavaScriptEscapesSingleQuotes() {
        let messageID = UUID()
        let context = MarkdownWebRendererCoordinatorSupport.SelectionContext(
            messageID: messageID,
            anchorID: "anchor'one"
        )

        XCTAssertTrue(context.javascript.contains("setSelectionContext('\(messageID.uuidString)', '',"))
        XCTAssertTrue(context.javascript.contains("anchor\\'one"))
    }

    func testCoordinatorSupportDecodeSelectionSnapshotParsesRequiredAndOptionalFields() throws {
        let messageID = UUID()
        let matchingHighlightID = UUID()

        let snapshot = try XCTUnwrap(MarkdownWebRendererCoordinatorSupport.decodeSelectionSnapshot([
            "messageID": messageID.uuidString,
            "anchorID": "anchor-1",
            "selectedText": "selected text",
            "prefixContext": "before",
            "suffixContext": "after",
            "startOffset": NSNumber(value: 12),
            "endOffset": NSNumber(value: 25),
            "matchingHighlightIDs": [
                matchingHighlightID.uuidString,
                "not-a-uuid"
            ]
        ]))

        XCTAssertEqual(snapshot.messageID, messageID)
        XCTAssertEqual(snapshot.anchorID, "anchor-1")
        XCTAssertEqual(snapshot.selectedText, "selected text")
        XCTAssertEqual(snapshot.prefixContext, "before")
        XCTAssertEqual(snapshot.suffixContext, "after")
        XCTAssertEqual(snapshot.startOffset, 12)
        XCTAssertEqual(snapshot.endOffset, 25)
        XCTAssertEqual(snapshot.matchingHighlightIDs, [matchingHighlightID])
    }

    func testCoordinatorSupportPersistedHighlightsPayloadFiltersByAnchor() throws {
        let firstHighlight = MessageHighlightSnapshot(
            messageID: UUID(),
            anchorID: "anchor-1",
            selectedText: "first",
            startOffset: 0,
            endOffset: 5
        )
        let secondHighlight = MessageHighlightSnapshot(
            messageID: UUID(),
            anchorID: "anchor-2",
            selectedText: "second",
            startOffset: 8,
            endOffset: 14
        )

        let payload = try MarkdownWebRendererCoordinatorSupport.persistedHighlightsPayload(
            [firstHighlight, secondHighlight],
            selectionAnchorID: "anchor-1"
        )
        let decoded = try JSONDecoder().decode(
            [MessageHighlightSnapshot].self,
            from: try XCTUnwrap(payload.data(using: .utf8))
        )

        XCTAssertEqual(decoded, [firstHighlight])
        XCTAssertEqual(
            try MarkdownWebRendererCoordinatorSupport.persistedHighlightsPayload(
                [firstHighlight, secondHighlight],
                selectionAnchorID: nil
            ),
            "[]"
        )
    }
}
