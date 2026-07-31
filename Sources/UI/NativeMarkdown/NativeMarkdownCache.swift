import Combine
import Foundation
import Markdown
import os

/// Process-wide LRU cache for parsed markdown blocks. Per-view caches died
/// with the view (`@StateObject`), so opening a long conversation re-parsed
/// every message even when the user had just scrolled past it a second ago.
/// Lives for the app's lifetime; capped to bound memory.
enum NativeMarkdownCache {
    struct Key: Hashable, Sendable {
        let markdownText: String
        let isStreaming: Bool
        let renderPlainText: Bool
        let appFontFamily: String
        let codeFontFamily: String

        /// Precomputed once when the render request is created. The synthesized
        /// `Hashable` implementation used to hash the full markdown payload on
        /// every LRU lookup, `.task(id:)` comparison, and in-flight lookup. A
        /// growing streaming response therefore paid O(document length) several
        /// times per UI flush before parsing even began.
        let contentFingerprint: UInt64
        let contentByteCount: Int

        init(
            markdownText: String,
            isStreaming: Bool,
            renderPlainText: Bool,
            appFontFamily: String,
            codeFontFamily: String
        ) {
            self.markdownText = markdownText
            self.isStreaming = isStreaming
            self.renderPlainText = renderPlainText
            self.appFontFamily = appFontFamily
            self.codeFontFamily = codeFontFamily
            var fingerprint = FNVHasher()
            fingerprint.combine(markdownText)
            self.contentFingerprint = fingerprint.value
            self.contentByteCount = markdownText.utf8.count
        }

        static func == (lhs: Key, rhs: Key) -> Bool {
            lhs.isStreaming == rhs.isStreaming
                && lhs.renderPlainText == rhs.renderPlainText
                && lhs.appFontFamily == rhs.appFontFamily
                && lhs.codeFontFamily == rhs.codeFontFamily
                && lhs.contentByteCount == rhs.contentByteCount
                && lhs.contentFingerprint == rhs.contentFingerprint
                // Keep equality collision-safe. In the overwhelmingly common
                // case both strings share storage, so this is constant-time.
                && lhs.markdownText == rhs.markdownText
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(contentFingerprint)
            hasher.combine(contentByteCount)
            hasher.combine(isStreaming)
            hasher.combine(renderPlainText)
            hasher.combine(appFontFamily)
            hasher.combine(codeFontFamily)
        }
    }

    struct Value: @unchecked Sendable {
        let blocks: [NativeMarkdownBlock]
        let groups: [NativeMarkdownGroup]
        let layout: NativeAnchorLayout
    }

    struct PrewarmItem: Hashable, Sendable {
        let markdownText: String
        let renderPlainText: Bool
    }

    private static let capacity = 256
    /// Byte ceiling for the estimated size of cached parses. A count limit
    /// alone lets 256 code-heavy messages (each cached at roughly 10× its
    /// source size across blocks + groups + layout) grow into the hundreds of
    /// MB; typical conversations stay far below this budget, so eviction only
    /// kicks in where it matters.
    private static let costBudget = 32 * 1024 * 1024
    private static let storage = OSAllocatedUnfairLock<Storage>(
        initialState: Storage(capacity: capacity, costBudget: costBudget)
    )

    /// Full purge for memory-pressure response. Rows re-parse through the
    /// normal async coordinator path on their next lookup.
    static func purgeForMemoryPressure() {
        storage.withLock { $0.removeAll() }
    }

    /// Fires (throttled, on main) after inserts. Observing process-wide cache
    /// fills lets a recycled row adopt work completed by prewarm or another
    /// row without tying correctness to a particular SwiftUI task lifecycle.
    private static let insertSignal = PassthroughSubject<Void, Never>()
    static let insertNotifications: AnyPublisher<Void, Never> = insertSignal
        .throttle(for: .milliseconds(120), scheduler: DispatchQueue.main, latest: true)
        .eraseToAnyPublisher()

    static func tryGet(key: Key) -> Value? {
        storage.withLock { $0.lookup(key) }
    }

    static func insert(_ value: Value, forKey key: Key) {
        storage.withLock { $0.insert(value, forKey: key) }
        insertSignal.send()
    }

    static func get(key: Key, theme: MarkdownTheme) -> Value {
        if let cached = tryGet(key: key) { return cached }
        let value = compute(key: key, theme: theme)
        insert(value, forKey: key)
        return value
    }

    /// Off-main pre-warm. Given the text payloads that will eventually be
    /// rendered by `NativeMarkdownView`, computes each with the same
    /// plain-text-vs-markdown mode the row will use so the LRU is populated
    /// before the recycling timeline instantiates the corresponding row.
    /// Eliminates the placeholder → content swap users see when scrolling
    /// into a fresh message in a long conversation.
    ///
    /// `items` are consumed front-to-back; callers that want the user's
    /// most-likely-visible messages cached first (e.g., the bottom of a
    /// pin-to-bottom chat timeline) should pre-reverse the input. Already-
    /// cached entries are skipped without dispatching, so re-invocations
    /// for a growing message list are cheap.
    ///
    /// Runs the per-item parse on a background `TaskGroup` with low bounded
    /// concurrency so pre-warm cannot steal every core from the foreground
    /// TextKit layout happening during conversation open. Returns a `Task`
    /// the caller can cancel.
    @discardableResult
    @MainActor
    static func prewarm(
        items: [PrewarmItem],
        appFontFamily: String,
        codeFontFamily: String,
        concurrency: Int = 2
    ) -> Task<Void, Never> {
        guard !items.isEmpty else {
            return Task {}
        }
        // Defend against a misconfigured caller passing 0 or a negative
        // value, which would make the seeding loop skip every text.
        let workerCount = max(1, concurrency)
        let theme = MarkdownTheme.resolved(
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily
        )
        return Task.detached(priority: .utility) {
            await warm(
                items: items,
                appFontFamily: appFontFamily,
                codeFontFamily: codeFontFamily,
                theme: theme,
                workerCount: workerCount,
                priority: .utility
            )
        }
    }

    /// Completes the stable parse before a streaming row is replaced by its
    /// persisted message row. The user keeps seeing the already-laid-out stream
    /// while this runs, then the final row lands as a synchronous LRU hit instead
    /// of exposing raw Markdown for an unbounded placeholder interval.
    @MainActor
    static func prepareForImmediateDisplay(
        items: [PrewarmItem],
        appFontFamily: String,
        codeFontFamily: String,
        concurrency: Int = 2
    ) async {
        guard !items.isEmpty else { return }
        let theme = MarkdownTheme.resolved(
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily
        )
        await warm(
            items: items,
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily,
            theme: theme,
            workerCount: max(1, concurrency),
            priority: .userInitiated
        )
    }

    private static func warm(
        items: [PrewarmItem],
        appFontFamily: String,
        codeFontFamily: String,
        theme: MarkdownTheme,
        workerCount: Int,
        priority: TaskPriority
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var iterator = items.makeIterator()

            @Sendable func makeChild(_ item: PrewarmItem) -> (@Sendable () async -> Void) {
                {
                    if Task.isCancelled { return }
                    let text = item.markdownText
                    guard !text.isEmpty else { return }
                    let key = Key(
                        markdownText: text,
                        isStreaming: false,
                        renderPlainText: item.renderPlainText,
                        appFontFamily: appFontFamily,
                        codeFontFamily: codeFontFamily
                    )
                    guard tryGet(key: key) == nil else { return }
                    _ = await NativeMarkdownParseService.parse(
                        key: key,
                        theme: theme,
                        priority: priority
                    )
                }
            }

            while inFlight < workerCount, let next = iterator.next() {
                group.addTask(operation: makeChild(next))
                inFlight += 1
            }
            while await group.next() != nil {
                if Task.isCancelled { break }
                if let next = iterator.next() {
                    group.addTask(operation: makeChild(next))
                }
            }
        }
    }

    static func compute(key: Key, theme: MarkdownTheme) -> Value {
        if key.renderPlainText {
            let block = NativeMarkdownBlock.paragraph(InlineRun(
                attributedString: NSAttributedString(
                    string: key.markdownText,
                    attributes: [.font: theme.bodyFont, .foregroundColor: theme.baseColor]
                ),
                plainText: key.markdownText,
                linkURLs: []
            ))
            let groups = NativeMarkdownGroupBuilder.build(blocks: [block], theme: theme)
            let layout = NativeAnchorLayoutBuilder.build(groups: groups)
            return Value(blocks: [block], groups: groups, layout: layout)
        }

        let repaired = MarkdownRenderPreparation.prepareForRender(key.markdownText, isStreaming: key.isStreaming).text
        let preprocessed = MarkdownExtensionPreprocessor.preprocess(repaired)
        // NOTE: `.parseBlockDirectives` is deliberately absent. Nothing in
        // the app consumes `BlockDirective` nodes, and with the option on,
        // ordinary prose like `@media (max-width: 600px) { … }` or
        // `@Observable class Foo` parses as a directive that consumes the
        // following lines into its children — mangling visible content.
        let document = Document(parsing: preprocessed, options: [.parseSymbolLinks])
        let walker = MarkdownASTWalker(theme: theme, isStreaming: key.isStreaming)
        let blocks = walker.walk(document: document)
        let groups = NativeMarkdownGroupBuilder.build(blocks: blocks, theme: theme)
        let layout = NativeAnchorLayoutBuilder.build(groups: groups)
        return Value(blocks: blocks, groups: groups, layout: layout)
    }
}

extension NativeMarkdownCache {
    fileprivate struct Storage {
        private struct Entry {
            let value: Value
            let cost: Int
            var lastAccess: UInt64
        }

        private var entries: [Key: Entry] = [:]
        private var accessClock: UInt64 = 0
        private var totalCost = 0
        let capacity: Int
        let costBudget: Int

        init(capacity: Int, costBudget: Int) {
            self.capacity = capacity
            self.costBudget = costBudget
        }

        mutating func lookup(_ key: Key) -> Value? {
            guard var entry = entries[key] else { return nil }
            accessClock &+= 1
            entry.lastAccess = accessClock
            entries[key] = entry
            return entry.value
        }

        mutating func insert(_ value: Value, forKey key: Key) {
            accessClock &+= 1
            // ~10× source size covers the three parallel representations in a
            // Value (per-block attributed strings, combined group strings,
            // anchor-layout flat text) plus struct overhead.
            let cost = 512 + key.contentByteCount * 10
            if let replaced = entries[key] {
                totalCost -= replaced.cost
            }
            entries[key] = Entry(value: value, cost: cost, lastAccess: accessClock)
            totalCost += cost
            while entries.count > capacity || totalCost > costBudget {
                guard entries.count > 1, let evicted = entries.min(by: {
                    $0.value.lastAccess < $1.value.lastAccess
                }) else { break }
                totalCost -= evicted.value.cost
                entries[evicted.key] = nil
            }
        }

        mutating func removeAll() {
            entries.removeAll()
            totalCost = 0
        }
    }
}
