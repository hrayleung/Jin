import AppKit
import WebKit
import os

/// Process-wide prewarmer for the `WKWebView`s that host mermaid rendering.
/// Each `MiniWebViewHost` instance takes 200-500 ms to instantiate on first
/// use because WebKit has to spin up the web content process and parse the
/// (large) Mermaid JS bundle before the first render can run.
///
/// The prewarm is demand-driven: the markdown group builder calls
/// `requestPrewarm()` the moment a mermaid block first appears in a parsed
/// message, which is well before the block is scrolled into view, so the
/// spin-up still happens off the user's interaction path. Warming at launch
/// instead would keep a WebKit web content process (~tens of MB) resident in
/// every session, including the majority that never render a mermaid block.
///
/// Once requested, the warm-up view is retained for the app's lifetime —
/// releasing it would let WebKit reap the content process and the next
/// mermaid block would pay the spin-up again.
@MainActor
enum MiniWebViewPrewarmer {
    private static var hasPrewarmed = false
    private static var retainedWarmupViews: [WKWebView] = []

    /// Cross-thread latch: the parse pipeline runs off the main actor and may
    /// see many mermaid blocks per second while streaming; only the first
    /// request pays the main-actor hop.
    private static let prewarmRequested = OSAllocatedUnfairLock(initialState: false)

    /// Fire-and-forget, callable from any thread. Safe to call repeatedly.
    nonisolated static func requestPrewarm() {
        let alreadyRequested = prewarmRequested.withLock { requested -> Bool in
            if requested { return true }
            requested = true
            return false
        }
        guard !alreadyRequested else { return }
        Task { @MainActor in
            prewarmIfNeeded()
        }
    }

    /// Idempotent; never blocks the caller.
    static func prewarmIfNeeded() {
        if hasPrewarmed { return }
        hasPrewarmed = true
        spawnWarmupView(templateName: "native-markdown-mermaid")
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
