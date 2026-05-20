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
    /// message in a long conversation. Skips entries that are already
    /// cached and bails on cancellation so a fast scroll doesn't waste
    /// cycles on stale work.
    static func prewarm(
        texts: [String],
        appFontFamily: String,
        codeFontFamily: String
    ) {
        guard !texts.isEmpty else { return }
        let theme = MarkdownTheme.resolved(
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily
        )
        Task.detached(priority: .utility) {
            for text in texts {
                if Task.isCancelled { return }
                guard !text.isEmpty else { continue }
                let key = Key(
                    markdownText: text,
                    isStreaming: false,
                    renderPlainText: false,
                    appFontFamily: appFontFamily,
                    codeFontFamily: codeFontFamily
                )
                if tryGet(key: key) != nil { continue }
                let value = compute(key: key, theme: theme)
                insert(value, forKey: key)
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
