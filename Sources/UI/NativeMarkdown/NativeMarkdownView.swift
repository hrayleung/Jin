import Markdown
import SwiftUI

/// Native SwiftUI/AppKit replacement for `MarkdownWebRenderer`.
///
/// Hot-path strategy:
/// 1. Try the process-wide LRU synchronously (free).
/// 2. If miss, render a one-shot plain-text placeholder synchronously and
///    ask the retained coordinator for an off-main parse — promotes once ready.
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
    /// Owns background work outside SwiftUI's cancellable `.task(id:)`
    /// lifecycle and coalesces growing streaming prefixes.
    @StateObject private var renderCoordinator = NativeMarkdownRenderCoordinator()

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
        // The retained async parse is reused only when it belongs to the
        // current content lineage:
        //  - same key (non-streaming first open: the async parse populates
        //    the coordinator output before the next body-level cache lookup,
        //    so that retained output is the source of truth in the window);
        //  - the current text is a growth of the parsed text under the same
        //    fonts/mode (streaming flushes mint a fresh key each ~100 ms, and
        //    the streaming→persisted swap reuses the final streaming parse —
        //    showing the last parse instead of flickering to the placeholder).
        // A recycled cell that kept this view's `@State` for a DIFFERENT
        // message fails the lineage test and falls back to the placeholder
        // rather than briefly rendering the previous row's content.
        let retained = renderCoordinator.output
        let parsed = syncHit ?? (isLineageMatch(current: key, parsed: retained?.key) ? retained?.value : nil)

        return Group {
            if let parsed {
                renderedBlocks(parsed: parsed, theme: theme)
            } else {
                placeholder(theme: theme)
            }
        }
        .onAppear {
            renderCoordinator.request(key: key, theme: theme)
        }
        .onChange(of: key) { _, newKey in
            renderCoordinator.request(key: newKey, theme: theme)
        }
        .onReceive(NativeMarkdownCache.insertNotifications) { _ in
            // Heals the placeholder-stuck state from OUTSIDE the view's own
            // lifecycle: targets the leaf view directly, so it works even
            // when the enclosing `.equatable()` gate prunes body re-evals
            // and the parse that produced the value was issued by another
            // view (prewarm, another cell). No-op once we already hold the
            // current key's parse. Streaming keys are never cached, so this
            // only fires for stable keys.
            guard renderCoordinator.output?.key != key,
                  let value = NativeMarkdownCache.tryGet(key: key) else { return }
            renderCoordinator.adopt(value, for: key)
        }
    }

    /// Whether a retained parse (produced for `parsed`) may stand in for the
    /// `current` key. True when they're the same key, or when `current` is a
    /// growth of `parsed` under identical fonts/mode — i.e. the same message
    /// streaming or finishing, NOT a different message that recycled into this
    /// view's preserved `@State`.
    private func isLineageMatch(
        current: NativeMarkdownCache.Key,
        parsed: NativeMarkdownCache.Key?
    ) -> Bool {
        renderCoordinator.output != nil
            && NativeMarkdownParseLineage.matches(current: current, retained: parsed)
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
        // Copy/Quote for standalone display-math blocks. Copy is always
        // available; Quote routes the raw LaTeX through the live aggregator
        // (which holds the freshest `onQuote` action), and is offered only when
        // the anchor is quotable — assistant messages pass a real
        // messageID/anchorID, user messages render with nil and get Copy-only.
        let mathActions = MarkdownMathSourceActions(
            copy: { PasteboardSupport.writeString($0) },
            quote: (selectionMessageID != nil && selectionAnchorID != nil)
                ? { [aggregator = aggregatorStore.aggregator] latex in aggregator.quoteRawSource(latex) }
                : nil
        )
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parsed.indexedGroups, id: \.id) { item in
                NativeGroupView(group: item.group, path: [item.position])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.markdownTheme, theme)
        .environment(\.nativeMarkdownAnchor, anchorContext)
        .environment(\.markdownMathSourceActions, mathActions)
        .environment(\.markdownDefersCodeHighlightUpgrade, deferCodeHighlightUpgrade)
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

/// Decides whether a retained parse may stand in for the current render key
/// (see `NativeMarkdownView`'s coordinator output reuse). Pure key comparison so it
/// can be unit-tested without a view.
enum NativeMarkdownParseLineage {
    /// True when `retained` produced content the `current` key may display:
    /// the same key, or `current` is a growth of `retained` under identical
    /// fonts/mode (the same message streaming or finishing). False for a
    /// different message — the recycled-cell stale-content case.
    static func matches(
        current: NativeMarkdownCache.Key,
        retained: NativeMarkdownCache.Key?
    ) -> Bool {
        guard let retained else { return false }
        if retained == current { return true }
        return current.renderPlainText == retained.renderPlainText
            && current.appFontFamily == retained.appFontFamily
            && current.codeFontFamily == retained.codeFontFamily
            && !retained.markdownText.isEmpty
            && current.markdownText.hasPrefix(retained.markdownText)
    }
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
