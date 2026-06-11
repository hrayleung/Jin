import Markdown
import SwiftUI

/// Native SwiftUI/AppKit replacement for `MarkdownWebRenderer`.
///
/// Hot-path strategy:
/// 1. Try the process-wide LRU synchronously (free).
/// 2. If miss, render a one-shot plain-text placeholder synchronously and
///    kick the real parse onto a background actor — promotes once ready.
/// 3. `SelectionAggregator` lives in `@StateObject` so it survives body
///    re-evaluations (no churn).
struct NativeMarkdownView: View {
    let markdownText: String
    var isStreaming: Bool = false
    var deferCodeHighlightUpgrade: Bool = false
    var renderPlainText: Bool = false
    var selectionMessageID: UUID? = nil
    var selectionAnchorID: String? = nil
    var persistedHighlights: [MessageHighlightSnapshot] = []
    var selectionActions: MessageTextSelectionActions = .none

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue

    @StateObject private var aggregatorStore = SelectionAggregatorStore()
    /// Most recent parse result. **Kept across cache-key changes during
    /// streaming**: when the markdown text grows every ~100 ms, each new
    /// key misses the cache and a fresh parse is dispatched. Without this
    /// retention the view would fall back to the plain-text placeholder
    /// between parses and the user would see the rendered NSTextView
    /// swap to raw markdown text every flush — that flicker is what gets
    /// perceived as "the AI streaming output is particularly laggy".
    @State private var asyncParsed: NativeMarkdownCache.Value?

    var body: some View {
        let theme = MarkdownTheme.resolved(appFontFamily: appFontFamily, codeFontFamily: codeFontFamily)
        let key = NativeMarkdownCache.Key(
            markdownText: markdownText,
            isStreaming: isStreaming,
            renderPlainText: renderPlainText,
            appFontFamily: appFontFamily,
            codeFontFamily: codeFontFamily
        )

        // Synchronous LRU hit — free, common case after first parse.
        let syncHit = NativeMarkdownCache.tryGet(key: key)
        // During streaming, every flush produces a fresh key (the markdown
        // grew). Falling back to the plain-text placeholder on every miss
        // makes the rendered subtree flicker between NSTextView and raw
        // `Text(markdownText)` at flush rate. Instead, retain whichever
        // parse result we last computed — even if it's a few flushes
        // stale, the in-progress streaming visual is dramatically smoother
        // than swapping the entire subtree out and back in. The next
        // parse will overwrite `asyncParsed` and the view catches up.
        //
        // The same fallback is also required on non-streaming first open:
        // the async parse populates `asyncParsed` first; the cache insert
        // is on a different thread and is not always visible to the next
        // `tryGet` issued from the body re-eval, so `asyncParsed` is the
        // only guaranteed source of truth in that window.
        let parsed = syncHit ?? asyncParsed

        return Group {
            if let parsed {
                renderedBlocks(parsed: parsed, theme: theme)
            } else {
                placeholder(theme: theme)
            }
        }
        .task(id: key) {
            guard syncHit == nil else { return }
            guard let value = await NativeMarkdownParseService.parse(key: key, theme: theme) else {
                return
            }
            guard !Task.isCancelled else { return }
            asyncParsed = value
        }
    }

    @ViewBuilder
    private func renderedBlocks(parsed: NativeMarkdownCache.Value, theme: MarkdownTheme) -> some View {
        let anchorContext = NativeMarkdownAnchorContext(
            aggregator: aggregatorStore.aggregator,
            layout: parsed.layout
        )
        let inputs = AggregatorInputs(
            messageID: selectionMessageID,
            anchorID: selectionAnchorID,
            blocks: parsed.layout.aggregatorBlocks,
            persistedHighlights: persistedHighlights
        )
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parsed.indexedGroups, id: \.id) { item in
                NativeGroupView(group: item.group, path: [item.position])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.markdownTheme, theme)
        .environment(\.nativeMarkdownAnchor, anchorContext)
        // Update the aggregator only when its inputs actually change. The
        // previous `let _ = aggregatorStore.update(...)` inside body ran on
        // every body re-eval, which in turn re-walked every block's
        // textStorage to re-apply highlights — the dominant per-frame cost
        // in long conversations.
        .onAppear {
            aggregatorStore.update(
                messageID: inputs.messageID,
                anchorID: inputs.anchorID,
                actions: selectionActions,
                blocks: inputs.blocks,
                persistedHighlights: inputs.persistedHighlights
            )
        }
        .onChange(of: inputs) { _, newInputs in
            aggregatorStore.update(
                messageID: newInputs.messageID,
                anchorID: newInputs.anchorID,
                actions: selectionActions,
                blocks: newInputs.blocks,
                persistedHighlights: newInputs.persistedHighlights
            )
        }
    }

    /// Composite key used to gate aggregator re-applies. Closures
    /// (`selectionActions`) are intentionally excluded — they may be
    /// rebuilt on every body call and would defeat the gate; the latest
    /// `selectionActions` is captured from the enclosing struct when the
    /// `.onChange` closure fires, which is good enough for menu intents.
    private struct AggregatorInputs: Equatable {
        let messageID: UUID?
        let anchorID: String?
        let blocks: [SelectionAggregator.BlockOffsetInfo]
        let persistedHighlights: [MessageHighlightSnapshot]
    }

    @ViewBuilder
    private func placeholder(theme: MarkdownTheme) -> some View {
        // Cheap fallback shown for the (typically 10-50 ms) window before
        // the async parse finishes. Uses SwiftUI Text — no NSTextView
        // allocation — and matches the eventual layout closely enough that
        // the swap is not visually jarring.
        Text(markdownText)
            .font(.body)
            .foregroundStyle(Color(nsColor: theme.baseColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0.85)
    }
}

extension NativeMarkdownCache.Value {
    /// Pre-computed `(NativeMarkdownBlockID, NativeMarkdownGroup)` pairs whose
    /// `ForEach` id is `(position, kind)` — NOT the content signature. Keying on
    /// the content signature meant the growing tail prose group got a fresh id
    /// every streaming flush, so SwiftUI tore down and rebuilt its
    /// `NSTextView` (a full TextKit-stack allocation + glyph layout from
    /// scratch) ~10x/sec. With a kind-based id the tail view is reused; the
    /// real `contentSignature` is still threaded down to
    /// `AttributedTextBlock`, which applies the new attributed string in place.
    var indexedGroups: [IndexedGroup] {
        groups.enumerated().map { offset, group in
            IndexedGroup(
                id: NativeMarkdownBlockID(position: offset, signature: group.kindTag),
                position: offset,
                group: group
            )
        }
    }

}

struct IndexedGroup: Identifiable {
    let id: NativeMarkdownBlockID
    let position: Int
    let group: NativeMarkdownGroup
}

/// Holder so we don't re-create `SelectionAggregator` on every body call.
@MainActor
final class SelectionAggregatorStore: ObservableObject {
    private(set) var aggregator: SelectionAggregator

    init() {
        self.aggregator = SelectionAggregator(
            messageID: nil,
            anchorID: nil,
            actions: .none,
            blocks: [],
            persistedHighlights: []
        )
    }

    /// Mutates the existing aggregator in place. We deliberately do NOT
    /// publish — the aggregator is referenced by descendant views that
    /// register themselves; mutations propagate through those registrations
    /// rather than via SwiftUI invalidation, which would cause body churn.
    func update(
        messageID: UUID?,
        anchorID: String?,
        actions: MessageTextSelectionActions,
        blocks: [SelectionAggregator.BlockOffsetInfo],
        persistedHighlights: [MessageHighlightSnapshot]
    ) {
        if aggregator.messageID != messageID || aggregator.anchorID != anchorID {
            aggregator.reset(
                messageID: messageID,
                anchorID: anchorID,
                actions: actions,
                blocks: blocks,
                persistedHighlights: persistedHighlights
            )
            return
        }
        aggregator.actions = actions
        aggregator.update(blocks: blocks, persistedHighlights: persistedHighlights)
    }
}

/// Off-main parsing actor. Documents up to ~30 KB parse in 5-30 ms; we keep
/// SwiftUI responsive by offloading. Use `enum` + `nonisolated static func`
/// (no actor) so multiple `.task(id:)` callers from different
/// `NativeMarkdownView`s can all parse in parallel — the cache itself is
/// already thread-safe (`OSAllocatedUnfairLock`). The previous `actor`
/// design serialised parse work and showed up as a visible queueing hitch
/// when several messages crossed into the viewport at once.
enum NativeMarkdownParseService {
    /// Run the parse on a background thread. Returns the freshly-computed
    /// (or cached) value. Cancellation cuts off the work if the caller's
    /// `.task` was torn down while parsing was in flight.
    ///
    /// Streaming keys (`key.isStreaming == true`) are **not written to the
    /// LRU**: every ~100 ms flush mints a fresh key with the
    /// growing-prefix markdown, and persisting all of them would fill the
    /// 256-slot cache within seconds, evicting every other conversation's
    /// finished-message entries. The streaming caller already retains
    /// the last parsed value in its own `@State`, so the cache layer
    /// doesn't need to.
    static func parse(
        key: NativeMarkdownCache.Key,
        theme: MarkdownTheme
    ) async -> NativeMarkdownCache.Value? {
        guard !Task.isCancelled else { return nil }
        if let cached = NativeMarkdownCache.tryGet(key: key) {
            return cached
        }
        let task = Task.detached(priority: .userInitiated) {
            if Task.isCancelled {
                return NativeMarkdownCache.tryGet(key: key)
            }
            if let cached = NativeMarkdownCache.tryGet(key: key) {
                return cached
            }
            let value = NativeMarkdownCache.compute(key: key, theme: theme)
            if !Task.isCancelled, !key.isStreaming {
                NativeMarkdownCache.insert(value, forKey: key)
            }
            return value
        }
        let value = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled else { return nil }
        return value
    }
}
