import SwiftUI
import WebKit

private let cachedTemplateHTML: String? = {
    guard let url = Bundle.module.url(forResource: "markdown-template", withExtension: "html") else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}()

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

        loadTemplate(into: webView)
        return webView
    }

    func updateNSView(_ webView: MarkdownWKWebView, context: Context) {
        context.coordinator.heightBinding = $contentHeight

        let bodyFont = resolvedBodyFontCSS()
        let codeFont = resolvedCodeFontCSS()
        let fontSize = resolvedBodyFontSize()
        let fontSizeCSS = cssPixelValue(fontSize)

        if context.coordinator.isReady {
            if bodyFont != context.coordinator.lastBodyFont
                || codeFont != context.coordinator.lastCodeFont
                || abs(fontSize - context.coordinator.lastFontSize) > 0.001 {
                context.coordinator.lastBodyFont = bodyFont
                context.coordinator.lastCodeFont = codeFont
                context.coordinator.lastFontSize = fontSize
                let js = "document.documentElement.style.setProperty('--body-font','\(bodyFont)');document.documentElement.style.setProperty('--code-font','\(codeFont)');document.documentElement.style.setProperty('--body-font-size','\(fontSizeCSS)px');"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            MarkdownWebRenderer.sendMarkdown(to: webView, markdown: markdownText)
        } else {
            context.coordinator.pendingMarkdown = markdownText
        }
    }

    private func loadTemplate(into webView: WKWebView) {
        guard var html = cachedTemplateHTML else { return }
        html = html
            .replacingOccurrences(of: "BODY_FONT_FAMILY", with: resolvedBodyFontCSS())
            .replacingOccurrences(of: "BODY_FONT_SIZE", with: "\(cssPixelValue(resolvedBodyFontSize()))px")
            .replacingOccurrences(of: "CODE_FONT_FAMILY", with: resolvedCodeFontCSS())
        webView.loadHTMLString(html, baseURL: nil)
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

    private func resolvedBodyFontSize() -> CGFloat {
        JinTypography.chatBodyPointSize(scale: JinTypography.defaultChatMessageScale)
    }

    private func cssPixelValue(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 100).rounded() / 100
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: MarkdownWKWebView?
        var heightBinding: Binding<CGFloat>?
        var isReady = false
        var pendingMarkdown: String?
        var lastBodyFont: String = ""
        var lastCodeFont: String = ""
        var lastFontSize: CGFloat = 0

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
