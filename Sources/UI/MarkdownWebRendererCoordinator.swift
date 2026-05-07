import SwiftUI
import WebKit
import os

private let markdownRendererCoordinatorLogger = Logger(subsystem: "com.jin.app", category: "MarkdownRenderer")

final class MarkdownWebRendererCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
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
    var appFontFamily: String = JinTypography.systemFontPreferenceValue
    var codeFontFamily: String = JinTypography.systemFontPreferenceValue
    var codeBlockDisplayMode: String = CodeBlockDisplayMode.expanded.rawValue
    var deferCodeHighlightUpgrade: Bool = false
    var codeBlockShowLineNumbers: Bool = false
    var codeBlockCollapseLineThreshold: Int = 25
    var renderPlainText = false
    let maximumContentHeight: CGFloat = MarkdownWebRendererCoordinatorSupport.maximumContentHeight
    var selectionMessageID: UUID?
    var selectionContextThreadID: UUID?
    var selectionAnchorID: String?
    var persistedHighlights: [MessageHighlightSnapshot] = []
    var lastBodyFont: String = ""
    var lastCodeFont: String = ""
    var lastFontSize: CGFloat = 0
    var lastCodeBlockShowLineNumbers: Bool?
    var lastCodeBlockCollapseLineThreshold: Int?
    private var lastSelectionContext: MarkdownWebRendererCoordinatorSupport.SelectionContext?
    private var lastAppliedHighlightsPayload: String?
    private var isObservingDefaults = false
    private var pendingHeightUpdate: CGFloat?
    private var isHeightUpdateEnqueued = false
    private var lastLoggedMarkdownCount = 0

    /// Records that markdown was embedded in the HTML template so that
    /// subsequent `renderMarkdownIfNeeded` calls skip duplicate work.
    func markContentEmbedded(
        _ markdown: String,
        deferCodeHighlightUpgrade: Bool
    ) {
        lastRenderedMarkdown = markdown
        lastRenderedDeferCodeHighlightUpgrade = deferCodeHighlightUpgrade
        lastRenderedPlainTextMode = false
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

    func applyCodeBlockDisplayMode(webView: WKWebView) {
        webView.evaluateJavaScript(
            MarkdownWebRendererSupport.codeBlockDisplayModeJavaScript(codeBlockDisplayMode),
            completionHandler: nil
        )
    }

    func applySelectionContextIfNeeded(webView: WKWebView) {
        let context = MarkdownWebRendererCoordinatorSupport.SelectionContext(
            messageID: selectionMessageID,
            contextThreadID: selectionContextThreadID,
            anchorID: selectionAnchorID
        )
        guard context != lastSelectionContext else { return }
        lastSelectionContext = context
        webView.evaluateJavaScript(context.javascript, completionHandler: nil)
    }

    func applyPersistedHighlightsIfNeeded(webView: WKWebView) {
        do {
            let payload = try MarkdownWebRendererCoordinatorSupport.persistedHighlightsPayload(
                persistedHighlights,
                selectionAnchorID: selectionAnchorID
            )
            guard payload != lastAppliedHighlightsPayload else { return }
            lastAppliedHighlightsPayload = payload
            webView.evaluateJavaScript("window.setPersistedHighlights(\(payload))", completionHandler: nil)
        } catch {
            markdownRendererCoordinatorLogger.warning(
                "Failed to encode persisted highlights for anchor \(self.selectionAnchorID ?? "", privacy: .public) count \(self.persistedHighlights.count, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func renderMarkdownIfNeeded(
        _ markdown: String,
        in webView: WKWebView,
        force: Bool = false,
        deferCodeHighlightUpgrade: Bool = false
    ) {
        let preparedResult = renderPlainText
            ? .passthrough(markdown)
            : MarkdownRenderPreparation.prepareForRender(
                markdown,
                isStreaming: isStreaming
            )
        let preparedMarkdown = preparedResult.text

        guard force
                || preparedMarkdown != lastRenderedMarkdown
                || deferCodeHighlightUpgrade != lastRenderedDeferCodeHighlightUpgrade
                || renderPlainText != lastRenderedPlainTextMode else {
            return
        }

        logLargeMarkdownIfNeeded(markdown)
        lastRenderedMarkdown = preparedMarkdown
        lastRenderedDeferCodeHighlightUpgrade = deferCodeHighlightUpgrade
        lastRenderedPlainTextMode = renderPlainText
        MarkdownWebRenderer.sendMarkdown(
            to: webView,
            markdown: preparedMarkdown,
            streaming: isStreaming,
            deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
            renderPlainText: renderPlainText
        )
    }

    /// Compares resolved CSS values against cached state. If changed, evaluates
    /// the CSS custom property update JS and returns `true`.
    @discardableResult
    func applyFontUpdateIfNeeded(appFontFamily: String, codeFontFamily: String, webView: WKWebView) -> Bool {
        let bodyCSS = MarkdownWebRendererSupport.resolvedBodyFontCSS(family: appFontFamily)
        let codeCSS = MarkdownWebRendererSupport.resolvedCodeFontCSS(family: codeFontFamily)
        let fontSize = JinTypography.chatBodyPointSize(scale: JinTypography.defaultChatMessageScale)

        guard bodyCSS != lastBodyFont
                || codeCSS != lastCodeFont
                || abs(fontSize - lastFontSize) > 0.001 else {
            return false
        }

        lastBodyFont = bodyCSS
        lastCodeFont = codeCSS
        lastFontSize = fontSize
        let js = MarkdownWebRendererSupport.fontUpdateJavaScript(
            bodyCSS: bodyCSS,
            codeCSS: codeCSS,
            fontSizeCSS: MarkdownWebRendererSupport.cssPixelValue(fontSize)
        )
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
        let js = MarkdownWebRendererSupport.codeBlockSettingsJavaScript(
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
            webView?.selectionSnapshot = MarkdownWebRendererCoordinatorSupport.decodeSelectionSnapshot(message.body)
            return
        }
        guard message.name == "heightChanged",
              let height = MarkdownWebRendererCoordinatorSupport.clampedHeight(
                from: message.body,
                maximumHeight: maximumContentHeight
              ) else { return }

        // Avoid mutating SwiftUI state synchronously during AppKit layout.
        enqueueHeightUpdate(height)
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

    private func logLargeMarkdownIfNeeded(_ markdown: String) {
        let count = markdown.count
        guard count >= largeMarkdownLogThreshold else {
            lastLoggedMarkdownCount = 0
            return
        }
        guard count - lastLoggedMarkdownCount >= largeMarkdownLogStep else { return }
        lastLoggedMarkdownCount = count

        markdownRendererCoordinatorLogger.notice(
            "Rendering large markdown payload (chars: \(count, privacy: .public), streaming: \(self.isStreaming, privacy: .public))"
        )
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
