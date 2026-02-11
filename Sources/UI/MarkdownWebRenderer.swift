import SwiftUI
import WebKit

private let sharedProcessPool = WKProcessPool()

private var _cachedTemplateHTML: String?
private func cachedTemplateHTML() -> String? {
    if let cached = _cachedTemplateHTML { return cached }
    guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html"),
          let html = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    _cachedTemplateHTML = html
    return html
}

struct MarkdownWebRenderer: NSViewRepresentable {
    let markdownText: String

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.chatMessageFontScale) private var chatMessageFontScale = JinTypography.defaultChatMessageScale

    private static func estimatedHeight(for text: String) -> CGFloat {
        let lines = max(1, CGFloat(text.utf8.count) / 80.0)
        return max(24, lines * 20.0)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MarkdownWKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = sharedProcessPool
        config.userContentController = WKUserContentController()
        config.userContentController.add(context.coordinator, name: "heightChanged")
        config.userContentController.add(context.coordinator, name: "copyText")

        let webView = MarkdownWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setContentHuggingPriority(.required, for: .vertical)
        webView.contentHeight = Self.estimatedHeight(for: markdownText)

        context.coordinator.webView = webView
        context.coordinator.pendingMarkdown = markdownText

        loadTemplate(into: webView)
        return webView
    }

    func updateNSView(_ webView: MarkdownWKWebView, context: Context) {
        let bodyFont = resolvedBodyFontCSS()
        let codeFont = resolvedCodeFontCSS()
        let fontSize = resolvedBodyFontSize()

        if context.coordinator.isReady {
            if bodyFont != context.coordinator.lastBodyFont
                || codeFont != context.coordinator.lastCodeFont
                || fontSize != context.coordinator.lastFontSize {
                context.coordinator.lastBodyFont = bodyFont
                context.coordinator.lastCodeFont = codeFont
                context.coordinator.lastFontSize = fontSize
                let js = "document.documentElement.style.setProperty('--body-font','\(bodyFont)');document.documentElement.style.setProperty('--code-font','\(codeFont)');document.documentElement.style.setProperty('--body-font-size','\(fontSize)px');"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            sendMarkdown(to: webView, markdown: markdownText)
        } else {
            context.coordinator.pendingMarkdown = markdownText
        }
    }

    private func loadTemplate(into webView: WKWebView) {
        guard var html = cachedTemplateHTML() else { return }
        html = html
            .replacingOccurrences(of: "BODY_FONT_FAMILY", with: resolvedBodyFontCSS())
            .replacingOccurrences(of: "BODY_FONT_SIZE", with: "\(resolvedBodyFontSize())px")
            .replacingOccurrences(of: "CODE_FONT_FAMILY", with: resolvedCodeFontCSS())
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func sendMarkdown(to webView: WKWebView, markdown: String) {
        guard let data = markdown.data(using: .utf8) else { return }
        let b64 = data.base64EncodedString()
        webView.evaluateJavaScript("window.updateWithBase64('\(b64)')", completionHandler: nil)
    }

    private func sendMarkdown(to webView: WKWebView, markdown: String) {
        Self.sendMarkdown(to: webView, markdown: markdown)
    }

    private func resolvedBodyFontCSS() -> String {
        if appFontFamily == JinTypography.systemFontPreferenceValue {
            return "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
        }
        return "'\(appFontFamily)', -apple-system, sans-serif"
    }

    private func resolvedCodeFontCSS() -> String {
        if codeFontFamily == JinTypography.systemFontPreferenceValue {
            return "'SF Mono', Menlo, monospace"
        }
        return "'\(codeFontFamily)', 'SF Mono', Menlo, monospace"
    }

    private func resolvedBodyFontSize() -> Int {
        let base = 14.0
        return Int(base * chatMessageFontScale)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: MarkdownWKWebView?
        var isReady = false
        var pendingMarkdown: String?
        var lastBodyFont: String = ""
        var lastCodeFont: String = ""
        var lastFontSize: Int = 0

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
                  let webView = webView,
                  webView.contentHeight != height else { return }
            webView.contentHeight = height
            webView.invalidateIntrinsicContentSize()
        }
    }
}

final class MarkdownWKWebView: WKWebView {
    var contentHeight: CGFloat = 0

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
