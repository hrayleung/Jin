import SwiftUI
import WebKit
import os

private let markdownRendererLogger = Logger(subsystem: "com.jin.app", category: "MarkdownRenderer")

private let markdownTemplateURL = JinResourceBundle.url(forResource: "markdown-template", withExtension: "html")

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

struct MarkdownWebRenderer: View {
    let markdownText: String
    var isStreaming: Bool = false
    var deferCodeHighlightUpgrade: Bool = false

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue

    @State private var contentHeight: CGFloat

    init(markdownText: String, isStreaming: Bool = false, deferCodeHighlightUpgrade: Bool = false) {
        self.markdownText = markdownText
        self.isStreaming = isStreaming
        self.deferCodeHighlightUpgrade = deferCodeHighlightUpgrade
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
            codeFontFamily: codeFontFamily
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
        deferCodeHighlightUpgrade: Bool = false
    ) {
        let fn = streaming ? "updateStreamingWithText" : "updateWithText"
        let options: [String: Any] = ["deferCodeHighlightUpgrade": deferCodeHighlightUpgrade]

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
            let optionsLiteral = deferCodeHighlightUpgrade
                ? "{deferCodeHighlightUpgrade:true}"
                : "{deferCodeHighlightUpgrade:false}"
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
    let codeFontFamily: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MarkdownWKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.userContentController.add(context.coordinator, name: "heightChanged")
        config.userContentController.add(context.coordinator, name: "copyText")

        let webView = MarkdownWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setContentHuggingPriority(.required, for: .vertical)

        context.coordinator.webView = webView
        context.coordinator.heightBinding = $contentHeight
        context.coordinator.pendingMarkdown = markdownText
        context.coordinator.currentMarkdown = markdownText
        context.coordinator.appFontFamily = appFontFamily
        context.coordinator.codeFontFamily = codeFontFamily
        context.coordinator.deferCodeHighlightUpgrade = deferCodeHighlightUpgrade
        context.coordinator.startObservingFontPreferences()

        loadTemplate(into: webView)
        return webView
    }

    func updateNSView(_ webView: MarkdownWKWebView, context: Context) {
        context.coordinator.heightBinding = $contentHeight
        context.coordinator.currentMarkdown = markdownText
        context.coordinator.isStreaming = isStreaming
        context.coordinator.deferCodeHighlightUpgrade = deferCodeHighlightUpgrade
        context.coordinator.appFontFamily = appFontFamily
        context.coordinator.codeFontFamily = codeFontFamily

        if context.coordinator.isReady {
            let didUpdateFonts = context.coordinator.applyFontUpdateIfNeeded(
                appFontFamily: appFontFamily,
                codeFontFamily: codeFontFamily,
                webView: webView
            )
            context.coordinator.renderMarkdownIfNeeded(
                markdownText,
                in: webView,
                force: didUpdateFonts,
                deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
            )
        } else {
            context.coordinator.pendingMarkdown = markdownText
        }
    }

    private func loadTemplate(into webView: WKWebView) {
        guard let templateURL = markdownTemplateURL else { return }
        webView.loadFileURL(templateURL, allowingReadAccessTo: templateURL.deletingLastPathComponent())
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
        private var lastRenderedMarkdown: String?
        private var lastRenderedDeferCodeHighlightUpgrade: Bool?
        var appFontFamily: String = JinTypography.systemFontPreferenceValue
        var codeFontFamily: String = JinTypography.systemFontPreferenceValue
        var deferCodeHighlightUpgrade: Bool = false
        var lastBodyFont: String = ""
        var lastCodeFont: String = ""
        var lastFontSize: CGFloat = 0
        private var isObservingDefaults = false
        private var pendingHeightUpdate: CGFloat?
        private var isHeightUpdateEnqueued = false
        private var lastLoggedMarkdownCount = 0

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

        func startObservingFontPreferences() {
            guard !isObservingDefaults else { return }
            isObservingDefaults = true
            let defaults = UserDefaults.standard
            defaults.addObserver(self, forKeyPath: AppPreferenceKeys.appFontFamily, options: [.new], context: nil)
            defaults.addObserver(self, forKeyPath: AppPreferenceKeys.codeFontFamily, options: [.new], context: nil)
        }

        deinit {
            if isObservingDefaults {
                let defaults = UserDefaults.standard
                defaults.removeObserver(self, forKeyPath: AppPreferenceKeys.appFontFamily)
                defaults.removeObserver(self, forKeyPath: AppPreferenceKeys.codeFontFamily)
            }
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == AppPreferenceKeys.appFontFamily || keyPath == AppPreferenceKeys.codeFontFamily {
                DispatchQueue.main.async { [weak self] in
                    self?.handleFontPreferenceChange()
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

        func renderMarkdownIfNeeded(
            _ markdown: String,
            in webView: WKWebView,
            force: Bool = false,
            deferCodeHighlightUpgrade: Bool = false
        ) {
            guard force
                    || markdown != lastRenderedMarkdown
                    || deferCodeHighlightUpgrade != lastRenderedDeferCodeHighlightUpgrade else {
                return
            }

            logLargeMarkdownIfNeeded(markdown)
            lastRenderedMarkdown = markdown
            lastRenderedDeferCodeHighlightUpgrade = deferCodeHighlightUpgrade
            MarkdownWebRenderer.sendMarkdown(
                to: webView,
                markdown: markdown,
                streaming: isStreaming,
                deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            _ = applyFontUpdateIfNeeded(
                appFontFamily: appFontFamily,
                codeFontFamily: codeFontFamily,
                webView: webView
            )
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
    }
}

final class MarkdownWKWebView: WKWebView {
    var contentHeight: CGFloat = 0

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // Keep this subtree out of drag-destination resolution so outer
        // SwiftUI `.onDrop` handlers can detect hovering consistently.
        disableDragDestinationRecursively()
        DispatchQueue.main.async { [weak self] in
            self?.disableDragDestinationRecursively()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disableDragDestinationRecursively()
    }

    override func layout() {
        super.layout()
        disableDragDestinationRecursively()
    }

    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        // No-op: WKWebView internally re-registers drag types after web
        // content loads, which silently intercepts drag events that should
        // reach ChatView's .onDrop handler. Blocking re-registration ensures
        // drag-and-drop pass-through remains stable.
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        super.concludeDragOperation(sender)
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

    private func disableDragDestinationRecursively() {
        var queue: [NSView] = [self]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            view.unregisterDraggedTypes()
            queue.append(contentsOf: view.subviews)
        }
    }
}
