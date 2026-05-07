import SwiftUI
import WebKit

struct MarkdownWebRenderer: View {
    let markdownText: String
    var isStreaming: Bool = false
    var deferCodeHighlightUpgrade: Bool = false
    var renderPlainText: Bool = false
    var selectionMessageID: UUID? = nil
    var selectionContextThreadID: UUID? = nil
    var selectionAnchorID: String? = nil
    var persistedHighlights: [MessageHighlightSnapshot] = []
    var selectionActions: MessageTextSelectionActions = .none

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeBlockShowLineNumbers) private var codeBlockShowLineNumbers = false
    @AppStorage(AppPreferenceKeys.codeBlockCollapseLineThreshold) private var codeBlockCollapseLineThreshold = 25
    @AppStorage(AppPreferenceKeys.codeBlockDisplayMode) private var codeBlockDisplayMode = CodeBlockDisplayMode.expanded.rawValue

    @State private var contentHeight: CGFloat

    init(
        markdownText: String,
        isStreaming: Bool = false,
        deferCodeHighlightUpgrade: Bool = false,
        renderPlainText: Bool = false,
        selectionMessageID: UUID? = nil,
        selectionContextThreadID: UUID? = nil,
        selectionAnchorID: String? = nil,
        persistedHighlights: [MessageHighlightSnapshot] = [],
        selectionActions: MessageTextSelectionActions = .none
    ) {
        self.markdownText = markdownText
        self.isStreaming = isStreaming
        self.deferCodeHighlightUpgrade = deferCodeHighlightUpgrade
        self.renderPlainText = renderPlainText
        self.selectionMessageID = selectionMessageID
        self.selectionContextThreadID = selectionContextThreadID
        self.selectionAnchorID = selectionAnchorID
        self.persistedHighlights = persistedHighlights
        self.selectionActions = selectionActions
        let estimated = Self.estimatedHeight(for: markdownText)
        self._contentHeight = State(initialValue: estimated)
    }

    var body: some View {
        MarkdownWebRendererRepresentable(
            markdownText: markdownText,
            isStreaming: isStreaming,
            deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
            contentHeight: $contentHeight,
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily,
            codeBlockShowLineNumbers: codeBlockShowLineNumbers,
            codeBlockCollapseLineThreshold: codeBlockCollapseLineThreshold,
            codeBlockDisplayMode: codeBlockDisplayMode,
            renderPlainText: renderPlainText,
            selectionMessageID: selectionMessageID,
            selectionContextThreadID: selectionContextThreadID,
            selectionAnchorID: selectionAnchorID,
            persistedHighlights: persistedHighlights,
            selectionActions: selectionActions
        )
        .frame(height: contentHeight)
    }

    static func estimatedHeight(for text: String) -> CGFloat {
        // Count actual newlines for a more accurate estimate than pure byte count.
        // Markdown renders more compactly than raw text (headings, code blocks, etc.)
        let newlineCount = CGFloat(text.filter { $0 == "\n" }.count)
        let lineEstimate = max(1, newlineCount + 1)
        return max(56, min(lineEstimate * 22.0, 600))
    }

    static func sendMarkdown(
        to webView: WKWebView,
        markdown: String,
        streaming: Bool = false,
        deferCodeHighlightUpgrade: Bool = false,
        renderPlainText: Bool = false
    ) {
        let fn = streaming ? "updateStreamingWithText" : "updateWithText"
        let options: [String: Any] = [
            "deferCodeHighlightUpgrade": deferCodeHighlightUpgrade,
            "renderPlainText": renderPlainText
        ]

        if #available(macOS 11.0, *) {
            webView.callAsyncJavaScript(
                "window.\(fn)(markdown, options)",
                arguments: [
                    "markdown": markdown,
                    "options": options
                ],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        } else {
            // Fallback: base64-encode to avoid string escaping issues.
            guard let data = markdown.data(using: .utf8) else { return }
            let b64 = data.base64EncodedString()
            let legacyFn = streaming ? "updateStreamingWithBase64" : "updateWithBase64"
            let optionsLiteral = "{deferCodeHighlightUpgrade:\(deferCodeHighlightUpgrade ? "true" : "false"),renderPlainText:\(renderPlainText ? "true" : "false")}"
            webView.evaluateJavaScript("window.\(legacyFn)('\(b64)', \(optionsLiteral))", completionHandler: nil)
        }
    }
}

private struct MarkdownWebRendererRepresentable: NSViewRepresentable {
    let markdownText: String
    let isStreaming: Bool
    let deferCodeHighlightUpgrade: Bool
    @Binding var contentHeight: CGFloat
    let appFontFamily: String
    @Environment(\.dropForwarderRef) private var dropForwarderRef
    let codeFontFamily: String
    let codeBlockShowLineNumbers: Bool
    let codeBlockCollapseLineThreshold: Int
    let codeBlockDisplayMode: String
    let renderPlainText: Bool
    let selectionMessageID: UUID?
    let selectionContextThreadID: UUID?
    let selectionAnchorID: String?
    let persistedHighlights: [MessageHighlightSnapshot]
    let selectionActions: MessageTextSelectionActions

    func makeCoordinator() -> MarkdownWebRendererCoordinator {
        MarkdownWebRendererCoordinator()
    }

    func makeNSView(context: Context) -> MarkdownWKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController = WKUserContentController()
        config.userContentController.add(context.coordinator, name: "heightChanged")
        config.userContentController.add(context.coordinator, name: "copyText")
        config.userContentController.add(context.coordinator, name: "selectionChanged")

        // Prevent the web content from independently handling drops.
        // Without this, WKWebView's internal web process processes dropped
        // files (e.g. saving images to the default directory) alongside
        // our performDragOperation override.
        let dropPrevention = WKUserScript(
            source: """
            document.addEventListener('dragover', function(e) { e.preventDefault(); }, true);
            document.addEventListener('drop', function(e) { e.preventDefault(); e.stopPropagation(); }, true);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(dropPrevention)

        let webView = MarkdownWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setContentHuggingPriority(.required, for: .vertical)
        webView.dropForwarderRef = dropForwarderRef

        context.coordinator.webView = webView
        context.coordinator.heightBinding = $contentHeight
        context.coordinator.currentMarkdown = markdownText
        context.coordinator.appFontFamily = appFontFamily
        context.coordinator.codeFontFamily = codeFontFamily
        context.coordinator.deferCodeHighlightUpgrade = deferCodeHighlightUpgrade
        context.coordinator.codeBlockShowLineNumbers = codeBlockShowLineNumbers
        context.coordinator.codeBlockCollapseLineThreshold = codeBlockCollapseLineThreshold
        context.coordinator.codeBlockDisplayMode = codeBlockDisplayMode
        context.coordinator.renderPlainText = renderPlainText
        context.coordinator.selectionMessageID = selectionMessageID
        context.coordinator.selectionContextThreadID = selectionContextThreadID
        context.coordinator.selectionAnchorID = selectionAnchorID
        context.coordinator.persistedHighlights = persistedHighlights
        context.coordinator.startObservingPreferences()
        webView.onQuoteSelection = selectionActions.onQuote
        webView.onCreateHighlight = selectionActions.onHighlight
        webView.onRemoveHighlights = selectionActions.onRemoveHighlights

        // For non-streaming messages, embed the markdown directly in the HTML
        // so the browser renders content during the initial page load instead
        // of waiting for a Swift→JS round-trip after didFinish.
        let preparedResult = renderPlainText
            ? .passthrough(markdownText)
            : MarkdownRenderPreparation.prepareForRender(
                markdownText,
                isStreaming: isStreaming
            )
        let markdownForRender = preparedResult.text
        let shouldEmbed = !renderPlainText
            && !isStreaming
            && !markdownForRender.isEmpty
            && MarkdownWebRendererSupport.inlineTemplate != nil
        if shouldEmbed {
            context.coordinator.pendingMarkdown = nil
            context.coordinator.markContentEmbedded(
                markdownForRender,
                deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
            )
        } else {
            context.coordinator.pendingMarkdown = markdownForRender
        }

        loadTemplate(
            into: webView,
            embedMarkdown: shouldEmbed ? markdownForRender : nil
        )
        return webView
    }

    func updateNSView(_ webView: MarkdownWKWebView, context: Context) {
        webView.dropForwarderRef = dropForwarderRef
        context.coordinator.heightBinding = $contentHeight
        context.coordinator.currentMarkdown = markdownText
        context.coordinator.isStreaming = isStreaming
        context.coordinator.deferCodeHighlightUpgrade = deferCodeHighlightUpgrade
        context.coordinator.appFontFamily = appFontFamily
        context.coordinator.codeFontFamily = codeFontFamily
        context.coordinator.codeBlockShowLineNumbers = codeBlockShowLineNumbers
        context.coordinator.codeBlockCollapseLineThreshold = codeBlockCollapseLineThreshold
        context.coordinator.renderPlainText = renderPlainText
        context.coordinator.selectionMessageID = selectionMessageID
        context.coordinator.selectionContextThreadID = selectionContextThreadID
        context.coordinator.selectionAnchorID = selectionAnchorID
        context.coordinator.persistedHighlights = persistedHighlights
        webView.onQuoteSelection = selectionActions.onQuote
        webView.onCreateHighlight = selectionActions.onHighlight
        webView.onRemoveHighlights = selectionActions.onRemoveHighlights

        let modeChanged = context.coordinator.codeBlockDisplayMode != codeBlockDisplayMode
        context.coordinator.codeBlockDisplayMode = codeBlockDisplayMode

        if context.coordinator.isReady {
            context.coordinator.applySelectionContextIfNeeded(webView: webView)
            let didUpdateFonts = context.coordinator.applyFontUpdateIfNeeded(
                appFontFamily: appFontFamily,
                codeFontFamily: codeFontFamily,
                webView: webView
            )
            let didUpdateCodeBlockSettings = context.coordinator.applyCodeBlockSettingsIfNeeded(
                showLineNumbers: codeBlockShowLineNumbers,
                collapseLineThreshold: codeBlockCollapseLineThreshold,
                webView: webView
            )
            if modeChanged {
                context.coordinator.applyCodeBlockDisplayMode(webView: webView)
            }
            context.coordinator.renderMarkdownIfNeeded(
                markdownText,
                in: webView,
                force: didUpdateFonts || didUpdateCodeBlockSettings || modeChanged,
                deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
            )
            context.coordinator.applyPersistedHighlightsIfNeeded(webView: webView)
        } else {
            context.coordinator.pendingMarkdown = markdownText
        }
    }

    private func loadTemplate(
        into webView: WKWebView,
        embedMarkdown: String? = nil
    ) {
        if let cached = MarkdownWebRendererSupport.inlineTemplate {
            var html = cached.html
            if let markdown = embedMarkdown {
                html = MarkdownWebRendererSupport.embedMarkdownBootstrap(
                    in: html,
                    markdown: markdown,
                    streaming: isStreaming,
                    deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
                    codeBlockDisplayMode: codeBlockDisplayMode,
                    codeBlockShowLineNumbers: codeBlockShowLineNumbers,
                    codeBlockCollapseLineThreshold: codeBlockCollapseLineThreshold
                )
            }
            webView.loadHTMLString(html, baseURL: cached.baseURL)
        } else if let templateURL = MarkdownWebRendererSupport.templateURL {
            webView.loadFileURL(templateURL, allowingReadAccessTo: templateURL.deletingLastPathComponent())
        }
    }

}
