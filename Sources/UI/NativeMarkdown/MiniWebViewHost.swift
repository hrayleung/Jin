import AppKit
import SwiftUI
import WebKit

/// Generic, narrowly-scoped `WKWebView` host for math + mermaid mini-views.
/// Loads a one-page HTML template, calls a configurable JS function with
/// the payload, and reports back the rendered height. Multiple instances
/// share the same `WKProcessPool` so the heavy JS payload (KaTeX, Mermaid)
/// loads only once per app process.
struct MiniWebViewHost: NSViewRepresentable {
    let templateName: String
    let renderFunction: String
    let payload: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        // macOS 12+ shares the web content process automatically, so we no
        // longer need an explicit `WKProcessPool`. The OS already caches
        // KaTeX/Mermaid JS across instances within a process.
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.userContentController.add(context.coordinator, name: "heightChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.heightBinding = $height
        context.coordinator.pendingPayload = payload
        context.coordinator.renderFunction = renderFunction

        if let url = Bundle.module.url(forResource: templateName, withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.heightBinding = $height
        context.coordinator.renderFunction = renderFunction
        if context.coordinator.lastPayload != payload {
            context.coordinator.lastPayload = payload
            if context.coordinator.isReady {
                context.coordinator.dispatchRender(into: webView, payload: payload)
            } else {
                context.coordinator.pendingPayload = payload
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // Release the JSC heap and the script message handler promptly so
        // we don't keep mermaid/katex runtime memory around when the block
        // scrolls off-screen.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightChanged")
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var heightBinding: Binding<CGFloat>?
        var renderFunction: String = ""
        var pendingPayload: String?
        var lastPayload: String?
        var isReady = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let pending = pendingPayload {
                pendingPayload = nil
                dispatchRender(into: webView, payload: pending)
            }
        }

        func dispatchRender(into webView: WKWebView, payload: String) {
            guard !renderFunction.isEmpty else { return }
            webView.callAsyncJavaScript(
                "window.\(renderFunction)(payload)",
                arguments: ["payload": payload],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "heightChanged",
                  let value = message.body as? NSNumber else { return }
            let h = CGFloat(truncating: value)
            guard let binding = heightBinding, abs(binding.wrappedValue - h) > 0.5 else { return }
            DispatchQueue.main.async {
                binding.wrappedValue = h
            }
        }
    }
}
