import SwiftUI
import WebKit
import os

private let markdownRendererLogger = Logger(subsystem: "com.jin.app", category: "MarkdownRenderer")

private let markdownTemplateURL = JinResourceBundle.url(forResource: "markdown-template", withExtension: "html")
private let inlineCoreRuntimePlaceholder = "<!-- INLINE_CORE_RUNTIME -->\n<script src=\"markdown-core-runtime.js\"></script>"

/// Pre-cached HTML template with `markdown-core-runtime.js` inlined so that
/// each WKWebView can load from an in-memory string instead of triggering
/// per-instance file I/O for both the template and its subresource.
/// The `baseURL` points to the resources directory so that lazily-loaded
/// scripts (Prism, KaTeX, Mermaid) still resolve via relative URLs.
/// Embeds a base64-encoded markdown payload into the cached HTML so that the
/// browser renders content during the initial page load — no Swift→JS round-trip.
private func embedMarkdownBootstrap(
    in html: String,
    markdown: String,
    streaming: Bool,
    deferCodeHighlightUpgrade: Bool,
    preferHardBreaks: Bool,
    codeBlockDisplayMode: String = CodeBlockDisplayMode.expanded.rawValue,
    codeBlockShowLineNumbers: Bool = false,
    codeBlockCollapseLineThreshold: Int = 25
) -> String {
    guard let data = markdown.data(using: .utf8) else { return html }
    let base64 = data.base64EncodedString()
    let fn = streaming ? "updateStreamingContent" : "updateContent"
    var optionFragments: [String] = []
    if deferCodeHighlightUpgrade {
        optionFragments.append("deferCodeHighlightUpgrade:true")
    }
    if preferHardBreaks {
        optionFragments.append("preferHardBreaks:true")
    }
    let options = "{\(optionFragments.joined(separator: ","))}"
    let modeEscaped = codeBlockDisplayMode.replacingOccurrences(of: "'", with: "\\'")
    let codeBlockSettings = codeBlockSettingsJavaScript(
        showLineNumbers: codeBlockShowLineNumbers,
        collapseLineThreshold: codeBlockCollapseLineThreshold
    )
    let script = "<script>setCodeBlockDisplayMode('\(modeEscaped)');\(codeBlockSettings)\(fn)('\(base64)',\(options));</script>"
    return html.replacingOccurrences(of: "</body>", with: script + "\n</body>")
}

private let inlineTemplate: (html: String, baseURL: URL)? = {
    guard let templateURL = markdownTemplateURL,
          let coreRuntimeURL = JinResourceBundle.url(forResource: "markdown-core-runtime", withExtension: "js"),
          let templateHTML = try? String(contentsOf: templateURL, encoding: .utf8),
          let coreRuntimeJS = try? String(contentsOf: coreRuntimeURL, encoding: .utf8) else {
        return nil
    }

    let replacement = "<script>\n\(coreRuntimeJS)\n</script>"
    let inlined: String

    if let range = templateHTML.range(of: inlineCoreRuntimePlaceholder) {
        inlined = templateHTML.replacingCharacters(in: range, with: replacement)
    } else {
        markdownRendererLogger.warning("Failed to inline markdown core runtime because template marker was not found.")
        inlined = templateHTML
    }

    return (html: inlined, baseURL: templateURL.deletingLastPathComponent())
}()

// MARK: - Shared CSS Helpers

private func resolvedFontCSS(family: String, fallback: String) -> String {
    if family == JinTypography.systemFontPreferenceValue {
        return fallback
    }
    return "'\(family)', \(fallback)"
}

private func resolvedBodyFontCSS(family: String) -> String {
    resolvedFontCSS(family: family, fallback: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif")
}

private func resolvedCodeFontCSS(family: String) -> String {
    resolvedFontCSS(family: family, fallback: "'SF Mono', Menlo, monospace")
}

private func cssPixelValue(_ value: CGFloat) -> String {
    let rounded = (Double(value) * 100).rounded() / 100
    if rounded.rounded() == rounded {
        return String(Int(rounded))
    }
    return String(rounded)
}

private func fontUpdateJavaScript(bodyCSS: String, codeCSS: String, fontSizeCSS: String) -> String {
    "document.documentElement.style.setProperty('--body-font',\"\(bodyCSS)\");"
    + "document.documentElement.style.setProperty('--code-font',\"\(codeCSS)\");"
    + "document.documentElement.style.setProperty('--body-font-size',\"\(fontSizeCSS)px\");"
}

private func codeBlockSettingsJavaScript(showLineNumbers: Bool, collapseLineThreshold: Int) -> String {
    return "if(typeof window.applyCodeBlockSettings==='function'){"
    + "window.applyCodeBlockSettings({showLineNumbers:\(showLineNumbers),collapseLineThreshold:\(collapseLineThreshold)});"
    + "}"
}

/// Per-window drop forwarding reference. Each ChatView creates one and
/// injects it into the environment so that all MarkdownWKWebView instances
/// within that window forward drops to the correct attachment pipeline.
final class DropForwarderRef {
    var onDragTargetChanged: ((Bool) -> Void)?
    var onPerformDrop: ((NSDraggingInfo) -> Bool)?
}

private struct DropForwarderRefKey: EnvironmentKey {
    static let defaultValue: DropForwarderRef? = nil
}

extension EnvironmentValues {
    var dropForwarderRef: DropForwarderRef? {
        get { self[DropForwarderRefKey.self] }
        set { self[DropForwarderRefKey.self] = newValue }
    }
}

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
    var normalizeMarkdownForModelID: String? = nil

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
        selectionActions: MessageTextSelectionActions = .none,
        normalizeMarkdownForModelID: String? = nil
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
        self.normalizeMarkdownForModelID = normalizeMarkdownForModelID
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
            selectionActions: selectionActions,
            normalizeMarkdownForModelID: normalizeMarkdownForModelID
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
        renderPlainText: Bool = false,
        preferHardBreaks: Bool = false
    ) {
        let fn = streaming ? "updateStreamingWithText" : "updateWithText"
        let options: [String: Any] = [
            "deferCodeHighlightUpgrade": deferCodeHighlightUpgrade,
            "renderPlainText": renderPlainText,
            "preferHardBreaks": preferHardBreaks
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
            let optionsLiteral = "{deferCodeHighlightUpgrade:\(deferCodeHighlightUpgrade ? "true" : "false"),renderPlainText:\(renderPlainText ? "true" : "false"),preferHardBreaks:\(preferHardBreaks ? "true" : "false")}"
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
    let normalizeMarkdownForModelID: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

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
        let normalizedResult = renderPlainText
            ? .passthrough(markdownText)
            : MarkdownRenderNormalizer.normalizeForRender(
                markdownText,
                modelID: normalizeMarkdownForModelID,
                isStreaming: isStreaming
            )
        let markdownForRender = normalizedResult.text
        let shouldEmbed = !renderPlainText && !isStreaming && !markdownForRender.isEmpty && inlineTemplate != nil
        if shouldEmbed {
            context.coordinator.pendingMarkdown = nil
            context.coordinator.markContentEmbedded(
                markdownForRender,
                deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
                preferHardBreaks: normalizedResult.preferHardBreaks
            )
        } else {
            context.coordinator.pendingMarkdown = markdownForRender
        }

        loadTemplate(
            into: webView,
            embedMarkdown: shouldEmbed ? markdownForRender : nil,
            preferHardBreaks: normalizedResult.preferHardBreaks
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
        context.coordinator.normalizeMarkdownForModelID = normalizeMarkdownForModelID
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
        embedMarkdown: String? = nil,
        preferHardBreaks: Bool = false
    ) {
        if let cached = inlineTemplate {
            var html = cached.html
            if let markdown = embedMarkdown {
                html = embedMarkdownBootstrap(
                    in: html,
                    markdown: markdown,
                    streaming: isStreaming,
                    deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
                    preferHardBreaks: preferHardBreaks,
                    codeBlockDisplayMode: codeBlockDisplayMode,
                    codeBlockShowLineNumbers: codeBlockShowLineNumbers,
                    codeBlockCollapseLineThreshold: codeBlockCollapseLineThreshold
                )
            }
            webView.loadHTMLString(html, baseURL: cached.baseURL)
        } else if let templateURL = markdownTemplateURL {
            webView.loadFileURL(templateURL, allowingReadAccessTo: templateURL.deletingLastPathComponent())
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let maxAllowedContentHeight: CGFloat = 200_000
        private let largeMarkdownLogThreshold = 120_000
        private let largeMarkdownLogStep = 60_000

        weak var webView: MarkdownWKWebView?
        var heightBinding: Binding<CGFloat>?
        var isReady = false
        var isStreaming = false
        var pendingMarkdown: String?
        var currentMarkdown: String?
        private(set) var lastRenderedMarkdown: String?
        private(set) var lastRenderedDeferCodeHighlightUpgrade: Bool?
        private(set) var lastRenderedPlainTextMode: Bool?
        private(set) var lastRenderedPreferHardBreaks: Bool?
        var appFontFamily: String = JinTypography.systemFontPreferenceValue
        var codeFontFamily: String = JinTypography.systemFontPreferenceValue
        var codeBlockDisplayMode: String = CodeBlockDisplayMode.expanded.rawValue
        var deferCodeHighlightUpgrade: Bool = false
        var codeBlockShowLineNumbers: Bool = false
        var codeBlockCollapseLineThreshold: Int = 25
        var renderPlainText = false
        var normalizeMarkdownForModelID: String?
        var selectionMessageID: UUID?
        var selectionContextThreadID: UUID?
        var selectionAnchorID: String?
        var persistedHighlights: [MessageHighlightSnapshot] = []
        var lastBodyFont: String = ""
        var lastCodeFont: String = ""
        var lastFontSize: CGFloat = 0
        var lastCodeBlockShowLineNumbers: Bool?
        var lastCodeBlockCollapseLineThreshold: Int?
        private var lastSelectionContextKey: String?
        private var lastAppliedHighlightsPayload: String?
        private var isObservingDefaults = false
        private var pendingHeightUpdate: CGFloat?
        private var isHeightUpdateEnqueued = false
        private var lastLoggedMarkdownCount = 0

        /// Records that markdown was embedded in the HTML template so that
        /// subsequent `renderMarkdownIfNeeded` calls skip duplicate work.
        func markContentEmbedded(
            _ markdown: String,
            deferCodeHighlightUpgrade: Bool,
            preferHardBreaks: Bool
        ) {
            lastRenderedMarkdown = markdown
            lastRenderedDeferCodeHighlightUpgrade = deferCodeHighlightUpgrade
            lastRenderedPlainTextMode = false
            lastRenderedPreferHardBreaks = preferHardBreaks
        }

        private func logLargeMarkdownIfNeeded(_ markdown: String) {
            let count = markdown.count
            guard count >= largeMarkdownLogThreshold else {
                lastLoggedMarkdownCount = 0
                return
            }
            guard count - lastLoggedMarkdownCount >= largeMarkdownLogStep else { return }
            lastLoggedMarkdownCount = count

            markdownRendererLogger.notice(
                "Rendering large markdown payload (chars: \(count, privacy: .public), streaming: \(self.isStreaming, privacy: .public))"
            )
        }

        func startObservingPreferences() {
            guard !isObservingDefaults else { return }
            isObservingDefaults = true
            let defaults = UserDefaults.standard
            defaults.addObserver(self, forKeyPath: AppPreferenceKeys.appFontFamily, options: [.new], context: nil)
            defaults.addObserver(self, forKeyPath: AppPreferenceKeys.codeFontFamily, options: [.new], context: nil)
            defaults.addObserver(self, forKeyPath: AppPreferenceKeys.codeBlockDisplayMode, options: [.new], context: nil)
            defaults.addObserver(self, forKeyPath: AppPreferenceKeys.codeBlockShowLineNumbers, options: [.new], context: nil)
            defaults.addObserver(self, forKeyPath: AppPreferenceKeys.codeBlockCollapseLineThreshold, options: [.new], context: nil)
        }

        deinit {
            if isObservingDefaults {
                let defaults = UserDefaults.standard
                defaults.removeObserver(self, forKeyPath: AppPreferenceKeys.appFontFamily)
                defaults.removeObserver(self, forKeyPath: AppPreferenceKeys.codeFontFamily)
                defaults.removeObserver(self, forKeyPath: AppPreferenceKeys.codeBlockDisplayMode)
                defaults.removeObserver(self, forKeyPath: AppPreferenceKeys.codeBlockShowLineNumbers)
                defaults.removeObserver(self, forKeyPath: AppPreferenceKeys.codeBlockCollapseLineThreshold)
            }
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == AppPreferenceKeys.appFontFamily || keyPath == AppPreferenceKeys.codeFontFamily {
                DispatchQueue.main.async { [weak self] in
                    self?.handleFontPreferenceChange()
                }
            } else if keyPath == AppPreferenceKeys.codeBlockDisplayMode
                        || keyPath == AppPreferenceKeys.codeBlockShowLineNumbers
                        || keyPath == AppPreferenceKeys.codeBlockCollapseLineThreshold {
                DispatchQueue.main.async { [weak self] in
                    self?.handleCodeBlockPreferenceChange()
                }
            } else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }

        private func handleFontPreferenceChange() {
            guard isReady, let webView else { return }

            let defaults = UserDefaults.standard
            let appFont = defaults.string(forKey: AppPreferenceKeys.appFontFamily) ?? JinTypography.systemFontPreferenceValue
            let codeFont = defaults.string(forKey: AppPreferenceKeys.codeFontFamily) ?? JinTypography.systemFontPreferenceValue

            let didUpdate = applyFontUpdateIfNeeded(
                appFontFamily: appFont,
                codeFontFamily: codeFont,
                webView: webView
            )

            if didUpdate, let md = currentMarkdown {
                renderMarkdownIfNeeded(
                    md,
                    in: webView,
                    force: true,
                    deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
                )
            }
        }

        private func handleCodeBlockPreferenceChange() {
            guard isReady, let webView else { return }

            let defaults = UserDefaults.standard
            let mode = defaults.string(forKey: AppPreferenceKeys.codeBlockDisplayMode) ?? CodeBlockDisplayMode.expanded.rawValue
            let showLineNumbers = AppPreferences.boolValue(
                forKey: AppPreferenceKeys.codeBlockShowLineNumbers,
                default: false,
                defaults: defaults
            )
            let collapseLineThreshold = defaults.object(forKey: AppPreferenceKeys.codeBlockCollapseLineThreshold) as? Int ?? 25
            codeBlockDisplayMode = mode
            codeBlockShowLineNumbers = showLineNumbers
            codeBlockCollapseLineThreshold = collapseLineThreshold
            applyCodeBlockDisplayMode(webView: webView)
            _ = applyCodeBlockSettingsIfNeeded(
                showLineNumbers: showLineNumbers,
                collapseLineThreshold: collapseLineThreshold,
                webView: webView
            )

            if let md = currentMarkdown {
                renderMarkdownIfNeeded(
                    md,
                    in: webView,
                    force: true,
                    deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
                )
            }
        }

        func applyCodeBlockDisplayMode(webView: WKWebView) {
            let escaped = codeBlockDisplayMode.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("setCodeBlockDisplayMode('\(escaped)')", completionHandler: nil)
        }

        func applySelectionContextIfNeeded(webView: WKWebView) {
            let key = [
                selectionMessageID?.uuidString ?? "",
                selectionContextThreadID?.uuidString ?? "",
                selectionAnchorID ?? ""
            ].joined(separator: "|")
            guard key != lastSelectionContextKey else { return }
            lastSelectionContextKey = key

            let messageID = selectionMessageID?.uuidString ?? ""
            let threadID = selectionContextThreadID?.uuidString ?? ""
            let anchorID = selectionAnchorID ?? ""
            let escapedMessageID = messageID.replacingOccurrences(of: "'", with: "\\'")
            let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "\\'")
            let escapedAnchorID = anchorID.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript(
                "window.setSelectionContext('\(escapedMessageID)', '\(escapedThreadID)', '\(escapedAnchorID)')",
                completionHandler: nil
            )
        }

        func applyPersistedHighlightsIfNeeded(webView: WKWebView) {
            let highlightsForAnchor: [MessageHighlightSnapshot]
            if let selectionAnchorID {
                highlightsForAnchor = persistedHighlights.filter { $0.anchorID == selectionAnchorID }
            } else {
                highlightsForAnchor = []
            }

            let encoder = JSONEncoder()
            let data: Data
            do {
                data = try encoder.encode(highlightsForAnchor)
            } catch {
                markdownRendererLogger.warning(
                    "Failed to encode persisted highlights for anchor \(self.selectionAnchorID ?? "", privacy: .public) count \(highlightsForAnchor.count, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return
            }
            guard let payload = String(data: data, encoding: .utf8) else {
                markdownRendererLogger.warning(
                    "Failed to convert persisted highlights payload to UTF-8 for anchor \(self.selectionAnchorID ?? "", privacy: .public)"
                )
                return
            }
            guard payload != lastAppliedHighlightsPayload else { return }
            lastAppliedHighlightsPayload = payload
            webView.evaluateJavaScript("window.setPersistedHighlights(\(payload))", completionHandler: nil)
        }

        func renderMarkdownIfNeeded(
            _ markdown: String,
            in webView: WKWebView,
            force: Bool = false,
            deferCodeHighlightUpgrade: Bool = false
        ) {
            let normalizedResult = renderPlainText
                ? .passthrough(markdown)
                : MarkdownRenderNormalizer.normalizeForRender(
                    markdown,
                    modelID: normalizeMarkdownForModelID,
                    isStreaming: isStreaming
                )
            let normalizedMarkdown = normalizedResult.text

            guard force
                    || normalizedMarkdown != lastRenderedMarkdown
                    || deferCodeHighlightUpgrade != lastRenderedDeferCodeHighlightUpgrade
                    || normalizedResult.preferHardBreaks != lastRenderedPreferHardBreaks
                    || renderPlainText != lastRenderedPlainTextMode else {
                return
            }

            logLargeMarkdownIfNeeded(markdown)
            lastRenderedMarkdown = normalizedMarkdown
            lastRenderedDeferCodeHighlightUpgrade = deferCodeHighlightUpgrade
            lastRenderedPlainTextMode = renderPlainText
            lastRenderedPreferHardBreaks = normalizedResult.preferHardBreaks
            MarkdownWebRenderer.sendMarkdown(
                to: webView,
                markdown: normalizedMarkdown,
                streaming: isStreaming,
                deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
                renderPlainText: renderPlainText,
                preferHardBreaks: normalizedResult.preferHardBreaks
            )
        }

        /// Compares resolved CSS values against cached state. If changed, evaluates
        /// the CSS custom property update JS and returns `true`.
        @discardableResult
        func applyFontUpdateIfNeeded(appFontFamily: String, codeFontFamily: String, webView: WKWebView) -> Bool {
            let bodyCSS = resolvedBodyFontCSS(family: appFontFamily)
            let codeCSS = resolvedCodeFontCSS(family: codeFontFamily)
            let fontSize = JinTypography.chatBodyPointSize(scale: JinTypography.defaultChatMessageScale)

            guard bodyCSS != lastBodyFont
                    || codeCSS != lastCodeFont
                    || abs(fontSize - lastFontSize) > 0.001 else {
                return false
            }

            lastBodyFont = bodyCSS
            lastCodeFont = codeCSS
            lastFontSize = fontSize
            let js = fontUpdateJavaScript(bodyCSS: bodyCSS, codeCSS: codeCSS, fontSizeCSS: cssPixelValue(fontSize))
            webView.evaluateJavaScript(js, completionHandler: nil)
            return true
        }

        @discardableResult
        func applyCodeBlockSettingsIfNeeded(
            showLineNumbers: Bool,
            collapseLineThreshold: Int,
            webView: WKWebView
        ) -> Bool {
            guard showLineNumbers != lastCodeBlockShowLineNumbers
                    || collapseLineThreshold != lastCodeBlockCollapseLineThreshold else {
                return false
            }

            lastCodeBlockShowLineNumbers = showLineNumbers
            lastCodeBlockCollapseLineThreshold = collapseLineThreshold
            let js = codeBlockSettingsJavaScript(
                showLineNumbers: showLineNumbers,
                collapseLineThreshold: collapseLineThreshold
            )
            webView.evaluateJavaScript(js, completionHandler: nil)
            return true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            _ = applyFontUpdateIfNeeded(
                appFontFamily: appFontFamily,
                codeFontFamily: codeFontFamily,
                webView: webView
            )
            _ = applyCodeBlockSettingsIfNeeded(
                showLineNumbers: codeBlockShowLineNumbers,
                collapseLineThreshold: codeBlockCollapseLineThreshold,
                webView: webView
            )
            applyCodeBlockDisplayMode(webView: webView)
            applySelectionContextIfNeeded(webView: webView)
            if let pending = pendingMarkdown {
                pendingMarkdown = nil
                currentMarkdown = pending
                renderMarkdownIfNeeded(
                    pending,
                    in: webView,
                    force: true,
                    deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
                )
            }
            applyPersistedHighlightsIfNeeded(webView: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "copyText", let text = message.body as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                return
            }
            if message.name == "selectionChanged" {
                webView?.selectionSnapshot = Self.decodeSelectionSnapshot(message.body)
                return
            }
            guard message.name == "heightChanged",
                  let height = message.body as? CGFloat,
                  height.isFinite else { return }

            // Avoid mutating SwiftUI state synchronously during AppKit layout.
            let clamped = min(max(height, 1), maxAllowedContentHeight)
            enqueueHeightUpdate(clamped)
        }

        private func enqueueHeightUpdate(_ height: CGFloat) {
            pendingHeightUpdate = height
            guard !isHeightUpdateEnqueued else { return }
            isHeightUpdateEnqueued = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isHeightUpdateEnqueued = false
                guard let nextHeight = self.pendingHeightUpdate else { return }
                self.pendingHeightUpdate = nil
                self.applyHeightUpdate(nextHeight)
            }
        }

        private func applyHeightUpdate(_ height: CGFloat) {
            guard let webView else { return }

            if abs(webView.contentHeight - height) > 0.5 {
                webView.contentHeight = height
                webView.invalidateIntrinsicContentSize()
            }

            if let binding = heightBinding, abs(binding.wrappedValue - height) > 0.5 {
                binding.wrappedValue = height
            }
        }

        private static func decodeSelectionSnapshot(_ body: Any) -> MessageSelectionSnapshot? {
            guard let dict = body as? [String: Any],
                  let messageIDRaw = dict["messageID"] as? String,
                  let messageID = UUID(uuidString: messageIDRaw),
                  let anchorID = dict["anchorID"] as? String,
                  let selectedText = dict["selectedText"] as? String else {
                return nil
            }

            let startOffset = (dict["startOffset"] as? NSNumber)?.intValue ?? 0
            let endOffset = (dict["endOffset"] as? NSNumber)?.intValue ?? 0
            let threadID = (dict["contextThreadID"] as? String).flatMap(UUID.init(uuidString:))
            let matchingHighlightIDs = (dict["matchingHighlightIDs"] as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))

            return MessageSelectionSnapshot(
                messageID: messageID,
                contextThreadID: threadID,
                anchorID: anchorID,
                selectedText: selectedText,
                prefixContext: dict["prefixContext"] as? String,
                suffixContext: dict["suffixContext"] as? String,
                startOffset: startOffset,
                endOffset: endOffset,
                matchingHighlightIDs: matchingHighlightIDs
            )
        }
    }
}

final class MarkdownWKWebView: WKWebView {
    var contentHeight: CGFloat = 0
    var selectionSnapshot: MessageSelectionSnapshot?
    var onQuoteSelection: ((MessageSelectionSnapshot) -> Void)?
    var onCreateHighlight: ((MessageSelectionSnapshot) -> Void)?
    var onRemoveHighlights: (([UUID]) -> Void)?

    // Drop forwarding — set per-instance via the SwiftUI environment so
    // each window's WKWebView instances forward drops to the correct
    // ChatView's attachment pipeline. Using a weak reference avoids
    // retaining stale state if the ChatView is torn down.
    weak var dropForwarderRef: DropForwarderRef?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard dropForwarderRef != nil else { return [] }
        dropForwarderRef?.onDragTargetChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropForwarderRef != nil ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropForwarderRef?.onDragTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropForwarderRef != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropForwarderRef?.onDragTargetChanged?(false)
        return dropForwarderRef?.onPerformDrop?(sender) ?? false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dropForwarderRef?.onDragTargetChanged?(false)
        // Intentionally do NOT call super — WKWebView's default
        // implementation sends drag data to the WebContent process.
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dropForwarderRef?.onDragTargetChanged?(false)
        // Intentionally do NOT call super — prevents WKWebView
        // from finalizing the drop in the WebContent process.
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width, height: contentHeight)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        nextResponder?.scrollWheel(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.items.removeAll { $0.identifier == .init("WKMenuItemIdentifierReload") }
        guard let selectionSnapshot, !selectionSnapshot.isEmpty else { return }

        if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }

        let quoteItem = NSMenuItem(title: "Quote", action: #selector(quoteSelection), keyEquivalent: "")
        quoteItem.target = self
        quoteItem.image = NSImage(systemSymbolName: "quote.opening", accessibilityDescription: nil)
        menu.addItem(quoteItem)

        let highlightItem = NSMenuItem(title: "Highlight", action: #selector(highlightSelection), keyEquivalent: "")
        highlightItem.target = self
        highlightItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
        menu.addItem(highlightItem)

        if !selectionSnapshot.matchingHighlightIDs.isEmpty {
            let removeItem = NSMenuItem(title: "Remove Highlight", action: #selector(removeHighlightsForSelection), keyEquivalent: "")
            removeItem.target = self
            removeItem.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil)
            menu.addItem(removeItem)
        }

        let copyItem = NSMenuItem(title: "Copy Selection", action: #selector(copySelectionText), keyEquivalent: "")
        copyItem.target = self
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copyItem)
    }

    override func keyDown(with event: NSEvent) {
        nextResponder?.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        nextResponder?.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        nextResponder?.flagsChanged(with: event)
    }

    @objc private func quoteSelection() {
        guard let selectionSnapshot else { return }
        onQuoteSelection?(selectionSnapshot)
    }

    @objc private func highlightSelection() {
        guard let selectionSnapshot else { return }
        onCreateHighlight?(selectionSnapshot)
    }

    @objc private func removeHighlightsForSelection() {
        guard let selectionSnapshot else { return }
        onRemoveHighlights?(selectionSnapshot.matchingHighlightIDs)
    }

    @objc private func copySelectionText() {
        guard let text = selectionSnapshot?.selectedText,
              !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
