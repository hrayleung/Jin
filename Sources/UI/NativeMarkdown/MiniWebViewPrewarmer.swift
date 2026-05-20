import AppKit
import WebKit

/// Process-wide prewarmer for the `WKWebView`s that host math (KaTeX) and
/// mermaid rendering. Each `MiniWebViewHost` instance currently takes
/// 200-500 ms to instantiate on first use because WebKit has to spin up
/// the web content process and parse the (large) KaTeX/Mermaid JS bundles
/// before the first render can run.
///
/// By instantiating one hidden warm-up `WKWebView` per template at app
/// launch and letting it finish loading, we move that 200-500 ms cost off
/// the user's interaction path: subsequent `MiniWebViewHost`s reuse the
/// already-warm web content process (the OS caches the JS bundles
/// in-process) and report ready in tens of ms instead of hundreds.
///
/// The prewarm views are retained for the app's lifetime — releasing them
/// would let WebKit reap the content process and we'd be back where we
/// started. Memory cost is a few MB per template, acceptable for the perf
/// win on every conversation that contains math or mermaid blocks.
@MainActor
enum MiniWebViewPrewarmer {
    private static var hasPrewarmed = false
    private static var retainedWarmupViews: [WKWebView] = []

    /// Fire-and-forget prewarm. Safe to call from `JinApp.body.onAppear` or
    /// the app launch coordinator — idempotent and never blocks the caller.
    /// We deliberately defer the actual web view instantiation by 1 second
    /// so it doesn't compete with the first window's frame budget.
    static func prewarmIfNeeded() {
        if hasPrewarmed { return }
        hasPrewarmed = true

        // Defer past the initial window flush so the prewarm doesn't
        // contend with first-frame layout. 1 s is well after the user is
        // looking at the chat UI and before they're likely to send a
        // message that asks for math/mermaid.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            spawnWarmupView(templateName: "native-markdown-katex")
            spawnWarmupView(templateName: "native-markdown-mermaid")
        }
    }

    /// Builds a single off-screen `WKWebView`, loads the template, and
    /// retains it so the underlying web content process and JS engine
    /// stay resident.
    private static func spawnWarmupView(templateName: String) {
        guard let url = Bundle.module.url(forResource: templateName, withExtension: "html") else {
            return
        }
        // Off-screen frame so even if the view briefly becomes part of a
        // window hierarchy nothing visible flashes.
        let webView = WKWebView(frame: NSRect(x: -10_000, y: -10_000, width: 1, height: 1))
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        retainedWarmupViews.append(webView)
    }
}
