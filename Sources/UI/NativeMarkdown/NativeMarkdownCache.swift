import Foundation
import Markdown
import os

/// Process-wide LRU cache for parsed markdown blocks. Per-view caches died
/// with the view (`@StateObject`), so opening a long conversation re-parsed
/// every message even when the user had just scrolled past it a second ago.
/// Lives for the app's lifetime; capped to bound memory.
enum NativeMarkdownCache {
    struct Key: Hashable {
        let markdownText: String
        let isStreaming: Bool
        let renderPlainText: Bool
        let appFontFamily: String
        let codeFontFamily: String
    }

    struct Value {
        let blocks: [NativeMarkdownBlock]
        let groups: [NativeMarkdownGroup]
        let layout: NativeAnchorLayout
    }

    private static let capacity = 256
    private static let storage = OSAllocatedUnfairLock<Storage>(initialState: Storage(capacity: capacity))

    static func tryGet(key: Key) -> Value? {
        storage.withLock { $0.lookup(key) }
    }

    static func insert(_ value: Value, forKey key: Key) {
        storage.withLock { $0.insert(value, forKey: key) }
    }

    static func get(key: Key, theme: MarkdownTheme) -> Value {
        if let cached = tryGet(key: key) { return cached }
        let value = compute(key: key, theme: theme)
        insert(value, forKey: key)
        return value
    }

    /// Off-main pre-warm. Given the markdown texts that will eventually be
    /// rendered (typically every `.text` content part across the messages
    /// currently in the SwiftUI timeline window), parses each in the
    /// background so the LRU is populated before `LazyVStack` lazily
    /// instantiates the corresponding `NativeMarkdownView`. Eliminates the
    /// placeholder → content swap users see when scrolling into a fresh
    /// message in a long conversation.
    ///
    /// `texts` is consumed front-to-back; callers that want the user's
    /// most-likely-visible messages cached first (e.g., the bottom of a
    /// pin-to-bottom chat timeline) should pre-reverse the input. Already-
    /// cached entries are skipped without dispatching, so re-invocations
    /// for a growing message list are cheap.
    ///
    /// Runs the per-text parse on a background `TaskGroup` with bounded
    /// concurrency so all available cores are used without flooding the
    /// dispatch queue on huge load-earlier expansions. Returns a `Task`
    /// the caller can cancel — splitting that responsibility onto the
    /// caller lets the SwiftUI view stop the previous wave the moment a
    /// new conversation opens, instead of letting orphan parses keep
    /// thrashing the CPU.
    @discardableResult
    static func prewarm(
        texts: [String],
        appFontFamily: String,
        codeFontFamily: String,
        concurrency: Int = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
    ) -> Task<Void, Never> {
        guard !texts.isEmpty else {
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
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                var iterator = texts.makeIterator()

                @Sendable func makeChild(_ text: String) -> (@Sendable () async -> Void) {
                    {
                        if Task.isCancelled { return }
                        guard !text.isEmpty else { return }
                        let key = Key(
                            markdownText: text,
                            isStreaming: false,
                            renderPlainText: false,
                            appFontFamily: appFontFamily,
                            codeFontFamily: codeFontFamily
                        )
                        if tryGet(key: key) != nil { return }
                        let value = compute(key: key, theme: theme)
                        insert(value, forKey: key)
                    }
                }

                // Seed the group up to the concurrency cap.
                while inFlight < workerCount, let next = iterator.next() {
                    group.addTask(operation: makeChild(next))
                    inFlight += 1
                }
                // Drain + refill: as each parse finishes we schedule the
                // next text, keeping `concurrency` parses in flight until
                // the input is exhausted. This bounds peak memory (we
                // never queue all N texts at once) and lets cancellation
                // short-circuit the remaining tail.
                while await group.next() != nil {
                    if Task.isCancelled { break }
                    if let next = iterator.next() {
                        group.addTask(operation: makeChild(next))
                    }
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
        let document = Document(parsing: preprocessed, options: [.parseBlockDirectives, .parseSymbolLinks])
        let walker = MarkdownASTWalker(theme: theme, isStreaming: key.isStreaming)
        let blocks = walker.walk(document: document)
        let groups = NativeMarkdownGroupBuilder.build(blocks: blocks, theme: theme)
        let layout = NativeAnchorLayoutBuilder.build(groups: groups)
        return Value(blocks: blocks, groups: groups, layout: layout)
    }
}

extension NativeMarkdownCache {
    fileprivate struct Storage {
        private struct Node {
            let key: Key
            let value: Value
        }

        private var order: [Key] = []
        private var entries: [Key: Value] = [:]
        let capacity: Int

        init(capacity: Int) {
            self.capacity = capacity
        }

        mutating func lookup(_ key: Key) -> Value? {
            guard let value = entries[key] else { return nil }
            if let idx = order.firstIndex(of: key) {
                order.remove(at: idx)
                order.append(key)
            }
            return value
        }

        mutating func insert(_ value: Value, forKey key: Key) {
            if entries[key] != nil {
                if let idx = order.firstIndex(of: key) { order.remove(at: idx) }
            }
            entries[key] = value
            order.append(key)
            while order.count > capacity {
                let evicted = order.removeFirst()
                entries[evicted] = nil
            }
        }
    }
}
