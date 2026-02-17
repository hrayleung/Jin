import SwiftUI
import WebKit

private let cachedTemplateHTML: String? = {
    guard let url = JinResourceBundle.url(forResource: "markdown-template", withExtension: "html") else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
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

struct MarkdownWebRenderer: View {
    let markdownText: String

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue

    @State private var contentHeight: CGFloat

    init(markdownText: String) {
        self.markdownText = markdownText
        let estimated = Self.estimatedHeight(for: markdownText)
        self._contentHeight = State(initialValue: estimated)
    }

    var body: some View {
        MarkdownWebRendererRepresentable(
            markdownText: markdownText,
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
        return max(24, min(lineEstimate * 22.0, 600))
    }

    static func sendMarkdown(to webView: WKWebView, markdown: String) {
        guard let data = markdown.data(using: .utf8) else { return }
        let b64 = data.base64EncodedString()
        webView.evaluateJavaScript("window.updateWithBase64('\(b64)')", completionHandler: nil)
    }
}

private struct MarkdownWebRendererRepresentable: NSViewRepresentable {
    let markdownText: String
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
        context.coordinator.startObservingFontPreferences()

        loadTemplate(into: webView)
        return webView
    }

    func updateNSView(_ webView: MarkdownWKWebView, context: Context) {
        context.coordinator.heightBinding = $contentHeight
        context.coordinator.currentMarkdown = markdownText

        if context.coordinator.isReady {
            context.coordinator.applyFontUpdateIfNeeded(
                appFontFamily: appFontFamily,
                codeFontFamily: codeFontFamily,
                webView: webView
            )
            MarkdownWebRenderer.sendMarkdown(to: webView, markdown: markdownText)
        } else {
            context.coordinator.pendingMarkdown = markdownText
        }
    }

    private func loadTemplate(into webView: WKWebView) {
        guard var html = cachedTemplateHTML else { return }
        let bodyCSS = resolvedBodyFontCSS(family: appFontFamily)
        let codeCSS = resolvedCodeFontCSS(family: codeFontFamily)
        let fontSize = currentBodyFontSize
        html = html
            .replacingOccurrences(of: "BODY_FONT_FAMILY", with: bodyCSS)
            .replacingOccurrences(of: "BODY_FONT_SIZE", with: "\(cssPixelValue(fontSize))px")
            .replacingOccurrences(of: "CODE_FONT_FAMILY", with: codeCSS)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private var currentBodyFontSize: CGFloat {
        JinTypography.chatBodyPointSize(scale: JinTypography.defaultChatMessageScale)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: MarkdownWKWebView?
        var heightBinding: Binding<CGFloat>?
        var isReady = false
        var pendingMarkdown: String?
        var currentMarkdown: String?
        var lastBodyFont: String = ""
        var lastCodeFont: String = ""
        var lastFontSize: CGFloat = 0
        private var isObservingDefaults = false

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
                MarkdownWebRenderer.sendMarkdown(to: webView, markdown: md)
            }
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
            if let pending = pendingMarkdown {
                pendingMarkdown = nil
                MarkdownWebRenderer.sendMarkdown(to: webView, markdown: pending)
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
                  let webView = webView else { return }

            let clamped = max(height, 1)
            if webView.contentHeight != clamped {
                webView.contentHeight = clamped
                webView.invalidateIntrinsicContentSize()
            }
            // Update the SwiftUI-observed height so LazyVStack re-layouts
            if heightBinding?.wrappedValue != clamped {
                heightBinding?.wrappedValue = clamped
            }
        }
    }
}

final class MarkdownWKWebView: WKWebView {
    var contentHeight: CGFloat = 0

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // Clear any drag types registered during init so drag events pass
        // through to the parent SwiftUI .onDrop handler on ChatView.
        unregisterDraggedTypes()
    }

    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        // No-op: WKWebView internally re-registers drag types after web
        // content loads, which silently intercepts drag events that should
        // reach ChatView's .onDrop handler. Blocking re-registration ensures
        // drag-and-drop pass-through remains stable.
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
}
