import CoreGraphics
import Foundation
import os

private let markdownRendererSupportLogger = Logger(subsystem: "com.jin.app", category: "MarkdownRenderer")

enum MarkdownWebRendererSupport {
    static let templateURL = JinResourceBundle.url(forResource: "markdown-template", withExtension: "html")

    private static let inlineCoreRuntimePlaceholder = "<!-- INLINE_CORE_RUNTIME -->\n<script src=\"markdown-core-runtime.js\"></script>"
    private static let inlineRenderRuntimePlaceholder = "<script src=\"markdown-render-runtime.js\"></script>"

    struct InlinedRuntimeTemplate {
        let html: String
        let didReplaceCoreRuntime: Bool
        let didReplaceRenderRuntime: Bool
    }

    /// Pre-cached HTML template with the markdown runtimes inlined so that
    /// each WKWebView can load from an in-memory string instead of triggering
    /// per-instance file I/O for the template's core renderer scripts.
    /// The `baseURL` points to the resources directory so that lazily-loaded
    /// scripts (Prism, KaTeX, Mermaid) still resolve via relative URLs.
    static let inlineTemplate: (html: String, baseURL: URL)? = {
        guard let templateURL,
              let coreRuntimeURL = JinResourceBundle.url(forResource: "markdown-core-runtime", withExtension: "js"),
              let renderRuntimeURL = JinResourceBundle.url(forResource: "markdown-render-runtime", withExtension: "js"),
              let templateHTML = try? String(contentsOf: templateURL, encoding: .utf8),
              let coreRuntimeJS = try? String(contentsOf: coreRuntimeURL, encoding: .utf8),
              let renderRuntimeJS = try? String(contentsOf: renderRuntimeURL, encoding: .utf8) else {
            return nil
        }

        let inlined = inlineRuntimeScripts(
            in: templateHTML,
            coreRuntimeJS: coreRuntimeJS,
            renderRuntimeJS: renderRuntimeJS
        )

        if !inlined.didReplaceCoreRuntime {
            markdownRendererSupportLogger.warning("Failed to inline markdown core runtime because template marker was not found.")
        }
        if !inlined.didReplaceRenderRuntime {
            markdownRendererSupportLogger.warning("Failed to inline markdown render runtime because template marker was not found.")
        }

        return (html: inlined.html, baseURL: templateURL.deletingLastPathComponent())
    }()

    static func inlineRuntimeScripts(
        in templateHTML: String,
        coreRuntimeJS: String,
        renderRuntimeJS: String
    ) -> InlinedRuntimeTemplate {
        let coreReplacement = "<script>\n\(coreRuntimeJS)\n</script>"
        let renderReplacement = "<script>\n\(renderRuntimeJS)\n</script>"
        var inlined = templateHTML
        var didReplaceCoreRuntime = false
        var didReplaceRenderRuntime = false

        if let range = inlined.range(of: inlineCoreRuntimePlaceholder) {
            inlined.replaceSubrange(range, with: coreReplacement)
            didReplaceCoreRuntime = true
        }

        if let range = inlined.range(of: inlineRenderRuntimePlaceholder) {
            inlined.replaceSubrange(range, with: renderReplacement)
            didReplaceRenderRuntime = true
        }

        return InlinedRuntimeTemplate(
            html: inlined,
            didReplaceCoreRuntime: didReplaceCoreRuntime,
            didReplaceRenderRuntime: didReplaceRenderRuntime
        )
    }

    /// Embeds a base64-encoded markdown payload into the cached HTML so that
    /// the browser renders content during the initial page load without a
    /// Swift-to-JavaScript round trip.
    static func embedMarkdownBootstrap(
        in html: String,
        markdown: String,
        streaming: Bool,
        deferCodeHighlightUpgrade: Bool,
        codeBlockDisplayMode: String = CodeBlockDisplayMode.expanded.rawValue,
        codeBlockShowLineNumbers: Bool = false,
        codeBlockCollapseLineThreshold: Int = 25
    ) -> String {
        guard let data = markdown.data(using: .utf8) else { return html }
        let base64 = data.base64EncodedString()
        let functionName = streaming ? "updateStreamingContent" : "updateContent"
        var optionFragments: [String] = []
        if deferCodeHighlightUpgrade {
            optionFragments.append("deferCodeHighlightUpgrade:true")
        }
        let options = "{\(optionFragments.joined(separator: ","))}"
        let script = "<script>"
        + codeBlockDisplayModeJavaScript(codeBlockDisplayMode)
        + codeBlockSettingsJavaScript(
            showLineNumbers: codeBlockShowLineNumbers,
            collapseLineThreshold: codeBlockCollapseLineThreshold
        )
        + "\(functionName)('\(base64)',\(options));"
        + "</script>"
        return html.replacingOccurrences(of: "</body>", with: script + "\n</body>")
    }

    static func resolvedFontCSS(family: String, fallback: String) -> String {
        if family == JinTypography.systemFontPreferenceValue {
            return fallback
        }
        return "'\(family)', \(fallback)"
    }

    static func resolvedBodyFontCSS(family: String) -> String {
        resolvedFontCSS(family: family, fallback: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif")
    }

    static func resolvedCodeFontCSS(family: String) -> String {
        resolvedFontCSS(family: family, fallback: "'SF Mono', Menlo, monospace")
    }

    static func cssPixelValue(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 100).rounded() / 100
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    static func fontUpdateJavaScript(bodyCSS: String, codeCSS: String, fontSizeCSS: String) -> String {
        "document.documentElement.style.setProperty('--body-font',\"\(bodyCSS)\");"
        + "document.documentElement.style.setProperty('--code-font',\"\(codeCSS)\");"
        + "document.documentElement.style.setProperty('--body-font-size',\"\(fontSizeCSS)px\");"
    }

    static func codeBlockDisplayModeJavaScript(_ codeBlockDisplayMode: String) -> String {
        let escaped = codeBlockDisplayMode.replacingOccurrences(of: "'", with: "\\'")
        return "setCodeBlockDisplayMode('\(escaped)');"
    }

    static func codeBlockSettingsJavaScript(showLineNumbers: Bool, collapseLineThreshold: Int) -> String {
        "if(typeof window.applyCodeBlockSettings==='function'){"
        + "window.applyCodeBlockSettings({showLineNumbers:\(showLineNumbers),collapseLineThreshold:\(collapseLineThreshold)});"
        + "}"
    }
}
