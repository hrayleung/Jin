import Foundation
import Kingfisher

/// Process-wide memory-pressure listener that sheds cache weight the system
/// cannot reclaim on its own. `NSCache`-backed caches already evict under
/// pressure via libcache, but the hand-rolled dictionary LRUs (markdown parse
/// cache, syntax-highlight cache) never do, and Kingfisher's own
/// memory-warning purge is iOS-only.
@MainActor
final class MemoryPressureResponder {
    static let shared = MemoryPressureResponder()

    private var source: DispatchSourceMemoryPressure?

    func installIfNeeded() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            MemoryPressureResponder.shed(for: event)
        }
        source.resume()
        self.source = source
    }

    /// All purge targets are internally synchronized, so this is safe from the
    /// dispatch handler without actor hops.
    private nonisolated static func shed(for event: DispatchSource.MemoryPressureEvent) {
        // Warning: drop caches whose refill is async and visually invisible —
        // remote images fall back to Kingfisher's disk store, highlights
        // re-run off-main.
        ImageCache.default.clearMemoryCache()
        MarkdownSyntaxHighlighter.purgeCacheForMemoryPressure()

        guard event.contains(.critical) else { return }
        // Critical: also drop the parse cache. Scrolling immediately after
        // may briefly show row placeholders while messages re-parse —
        // acceptable at this severity.
        NativeMarkdownCache.purgeForMemoryPressure()
    }
}
