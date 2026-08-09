import AppKit
import Combine
import Foundation

/// Per-anchor coordinator for selection and persisted highlights in the
/// native markdown renderer. One instance lives in each `NativeMarkdownView`
/// (i.e., one per `.text` `ContentPart`). It:
///
/// - Owns the flat selectable text for the anchor (concatenation of every
///   leaf narrative block's `plainText`, in render order).
/// - Tracks `BlockOffsetInfo` for each registered block.
/// - Receives selection changes from per-block `JinMessageTextView`s and
///   builds `MessageSelectionSnapshot`s with offsets translated to the
///   anchor's flat text.
/// - Resolves persisted highlight offsets to per-block local NSRanges and
///   re-paints those ranges when the model changes.
///
/// V1 limitation: a single user drag selects within one block at a time;
/// cross-block selection is not implemented. The persisted-highlight model
/// is unchanged on disk so this is purely a UI ceiling.
@MainActor
final class SelectionAggregator: ObservableObject {
    struct BlockOffsetInfo: Hashable {
        let id: UUID
        let offsetInAnchor: Int
        let plainText: String

        var length: Int { plainText.utf16.count }
    }

    private(set) var messageID: UUID?
    private(set) var anchorID: String?
    var actions: MessageTextSelectionActions

    private(set) var flatText: String = ""
    private(set) var blocks: [BlockOffsetInfo] = []
    private(set) var persistedHighlights: [MessageHighlightSnapshot] = []
    private(set) var lastSnapshot: MessageSelectionSnapshot?

    private var blockTextViews: [UUID: WeakRef<JinMessageTextView>] = [:]

    init(
        messageID: UUID?,
        anchorID: String?,
        actions: MessageTextSelectionActions,
        blocks: [BlockOffsetInfo],
        persistedHighlights: [MessageHighlightSnapshot]
    ) {
        self.messageID = messageID
        self.anchorID = anchorID
        self.actions = actions
        self.blocks = blocks
        self.persistedHighlights = persistedHighlights
        self.flatText = blocks.map(\.plainText).joined(separator: "\n")
    }

    func update(blocks: [BlockOffsetInfo], persistedHighlights: [MessageHighlightSnapshot]) {
        // Bail early when the offset map and highlight set are identical —
        // `applyHighlightsToAllBlocks` walks every block's textStorage and
        // enumerates the `.jinHighlightID` attribute on every call, which
        // used to fire on every SwiftUI body re-eval. After the call-site
        // moved into `.onChange`, this short-circuit is a defense-in-depth
        // for any path that still issues a no-op update.
        if self.blocks == blocks && self.persistedHighlights == persistedHighlights {
            return
        }
        let hadHighlights = !self.persistedHighlights.isEmpty
        self.blocks = blocks
        self.flatText = blocks.map(\.plainText).joined(separator: "\n")
        self.persistedHighlights = persistedHighlights
        // During streaming the tail block legitimately differs every flush;
        // when there is nothing painted and nothing to paint, skip the
        // textStorage walk entirely.
        guard hadHighlights || !persistedHighlights.isEmpty else { return }
        applyHighlightsToAllBlocks()
        refreshSnapshotMatchingHighlights()
    }

    func reset(
        messageID: UUID?,
        anchorID: String?,
        actions: MessageTextSelectionActions,
        blocks: [BlockOffsetInfo],
        persistedHighlights: [MessageHighlightSnapshot]
    ) {
        self.messageID = messageID
        self.anchorID = anchorID
        self.actions = actions
        self.blocks = blocks
        self.flatText = blocks.map(\.plainText).joined(separator: "\n")
        self.persistedHighlights = persistedHighlights
        self.lastSnapshot = nil
        applyHighlightsToAllBlocks()
    }

    /// `lastSnapshot.matchingHighlightIDs` is computed inside
    /// `selectionDidChange`. When the persisted-highlight list mutates
    /// while a selection is still active (e.g., another window adds or
    /// removes a highlight), the stored IDs go stale — context-menu
    /// intents like "remove highlights from current selection" would
    /// then act on the wrong set until the user re-selects. Re-derive
    /// them from the current selection bounds against the new list and
    /// preserve the snapshot's id so observers don't see this as a
    /// fresh selection event.
    private func refreshSnapshotMatchingHighlights() {
        guard let snapshot = lastSnapshot else { return }
        let refreshed = matchingHighlightIDs(global: (snapshot.startOffset, snapshot.endOffset))
        guard refreshed != snapshot.matchingHighlightIDs else { return }
        lastSnapshot = MessageSelectionSnapshot(
            id: snapshot.id,
            messageID: snapshot.messageID,
            anchorID: snapshot.anchorID,
            selectedText: snapshot.selectedText,
            prefixContext: snapshot.prefixContext,
            suffixContext: snapshot.suffixContext,
            startOffset: snapshot.startOffset,
            endOffset: snapshot.endOffset,
            matchingHighlightIDs: refreshed
        )
    }

    func register(blockID: UUID, textView: JinMessageTextView) {
        blockTextViews[blockID] = WeakRef(value: textView)
        guard !persistedHighlights.isEmpty else { return }
        applyHighlights(toBlock: blockID)
    }

    func unregister(blockID: UUID) {
        blockTextViews[blockID] = nil
    }

    // MARK: - Selection events

    func selectionDidChange(blockID: UUID, localRange: NSRange) {
        guard let messageID, let anchorID else { return }
        guard let block = blocks.first(where: { $0.id == blockID }) else { return }

        if localRange.length == 0 {
            // Selection cleared.
            lastSnapshot = nil
            return
        }

        let blockText = block.plainText as NSString
        let safeLocation = min(localRange.location, blockText.length)
        let safeLength = min(localRange.length, blockText.length - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        // Prefer the live text view's storage: it holds the inline-math
        // attachment glyphs tagged with `.jinInlineMathSource`, so the LaTeX
        // source can be substituted back in (the U+FFFC in `plainText` carries
        // no recoverable text). Offsets continue to index the raw U+FFFC
        // `plainText`/`flatText` — only this OUTGOING string is expanded, so
        // highlight persistence is untouched. U+200B (CJK emphasis repair) is
        // stripped here too — quotes/prompts must not carry invisible
        // characters. Falls back to the raw slice when no live view is
        // registered (e.g. a recycled cell), never worse than before.
        let selectedText = latexExpandedSelectedText(blockID: blockID, range: safeRange)
            ?? blockText.substring(with: safeRange).replacingOccurrences(of: "\u{200B}", with: "")

        let globalStart = block.offsetInAnchor + safeRange.location
        let globalEnd = globalStart + safeRange.length

        let prefix = makeContextSlice(endingBefore: globalStart, length: 48)
        let suffix = makeContextSlice(startingAt: globalEnd, length: 48)
        let matchingHighlights = matchingHighlightIDs(global: (globalStart, globalEnd))

        let snapshot = MessageSelectionSnapshot(
            messageID: messageID,
            anchorID: anchorID,
            selectedText: selectedText,
            prefixContext: prefix,
            suffixContext: suffix,
            startOffset: globalStart,
            endOffset: globalEnd,
            matchingHighlightIDs: matchingHighlights
        )
        lastSnapshot = snapshot
    }

    /// Builds the LaTeX-restored text for `range` (a local NSRange into the
    /// block's `plainText`, which is length-aligned with the live textStorage)
    /// by expanding inline-math attachment glyphs to their `.jinInlineMathSource`
    /// source. Returns nil when the text view is unregistered so the caller
    /// falls back to the raw `plainText` slice.
    private func latexExpandedSelectedText(blockID: UUID, range: NSRange) -> String? {
        guard let storage = blockTextViews[blockID]?.value?.textStorage else { return nil }
        let safeLocation = min(range.location, storage.length)
        let safeLength = min(range.length, storage.length - safeLocation)
        guard safeLength > 0 else { return nil }
        let substring = storage.attributedSubstring(
            from: NSRange(location: safeLocation, length: safeLength)
        )
        return JinMessageTextView.latexExpandedPlainString(from: substring)
    }

    // MARK: - Context-menu intents

    func performQuoteFromCurrentSelection() {
        guard let snapshot = lastSnapshot, !snapshot.isEmpty else { return }
        actions.onQuote(snapshot)
    }

    /// Quotes a whole standalone source string — e.g. a display-math block's
    /// LaTeX — that has no selectable position in any text block (the rendered
    /// `MTMathUILabel` is not part of the selectable flat text). Offsets are
    /// irrelevant for a quote (they only gate highlight intersection), so a
    /// zero range is used; this path never creates highlights. No-op when the
    /// anchor isn't quotable or the source is blank.
    func quoteRawSource(_ source: String) {
        guard let messageID, let anchorID,
              MessageSelectionSupport.normalizedSelectedText(source) != nil else { return }
        let snapshot = MessageSelectionSnapshot(
            messageID: messageID,
            anchorID: anchorID,
            selectedText: source,
            prefixContext: nil,
            suffixContext: nil,
            startOffset: 0,
            endOffset: 0,
            matchingHighlightIDs: []
        )
        actions.onQuote(snapshot)
    }

    func performHighlightFromCurrentSelection() {
        guard let snapshot = lastSnapshot, !snapshot.isEmpty else { return }
        actions.onHighlight(snapshot)
    }

    func performRemoveHighlightsFromCurrentSelection() {
        guard let snapshot = lastSnapshot else { return }
        guard !snapshot.matchingHighlightIDs.isEmpty else { return }
        actions.onRemoveHighlights(snapshot.matchingHighlightIDs)
    }

    var currentSelectionIsNonEmpty: Bool {
        guard let snapshot = lastSnapshot else { return false }
        return !snapshot.isEmpty
    }

    var currentSelectionIntersectsHighlight: Bool {
        guard let snapshot = lastSnapshot else { return false }
        return !snapshot.matchingHighlightIDs.isEmpty
    }

    // MARK: - Highlight painting

    func applyHighlightsToAllBlocks() {
        for block in blocks {
            applyHighlights(toBlock: block.id)
        }
    }

    private func applyHighlights(toBlock blockID: UUID) {
        guard let textView = blockTextViews[blockID]?.value,
              let block = blocks.first(where: { $0.id == blockID }) else { return }

        // Routed through the text view so this edit joins the same reentrancy
        // guard the content applies use. `register(blockID:textView:)` is
        // called from inside `AttributedTextBlock.updateNSView`, which AppKit
        // can re-enter from the middle of a storage edit — painting attributes
        // there would nest a second edit inside the first one's notification
        // fan-out. The view replays a turned-away mutation when the outer edit
        // unwinds, so no highlight is lost.
        let persistedHighlights = persistedHighlights
        textView.performStorageMutation { [weak self] storage in
            guard let self else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(.jinHighlightID, in: fullRange, options: []) { value, range, _ in
                if value != nil {
                    storage.removeAttribute(.backgroundColor, range: range)
                    storage.removeAttribute(.jinHighlightID, range: range)
                }
            }

            for highlight in persistedHighlights {
                guard self.intersects(highlight: highlight, with: block) else { continue }
                let blockLocalRange = self.blockLocalRange(for: highlight, in: block)
                guard blockLocalRange.length > 0 else { continue }
                storage.addAttributes(
                    [
                        .backgroundColor: highlight.colorStyle.color,
                        .jinHighlightID: highlight.id,
                    ],
                    range: blockLocalRange
                )
            }
        }
    }

    private func intersects(highlight: MessageHighlightSnapshot, with block: BlockOffsetInfo) -> Bool {
        let blockStart = block.offsetInAnchor
        let blockEnd = blockStart + block.length
        return highlight.startOffset < blockEnd && highlight.endOffset > blockStart
    }

    private func blockLocalRange(for highlight: MessageHighlightSnapshot, in block: BlockOffsetInfo) -> NSRange {
        let blockStart = block.offsetInAnchor
        let blockEnd = blockStart + block.length
        let clampedStart = max(highlight.startOffset, blockStart) - blockStart
        let clampedEnd = min(highlight.endOffset, blockEnd) - blockStart
        return NSRange(location: clampedStart, length: max(0, clampedEnd - clampedStart))
    }

    // MARK: - Helpers

    private func matchingHighlightIDs(global: (Int, Int)) -> [UUID] {
        persistedHighlights.compactMap { highlight in
            guard highlight.startOffset < global.1, highlight.endOffset > global.0 else { return nil }
            return highlight.id
        }
    }

    private func makeContextSlice(endingBefore offset: Int, length: Int) -> String {
        guard offset > 0 else { return "" }
        let safeOffset = min(offset, (flatText as NSString).length)
        let start = max(0, safeOffset - length)
        return (flatText as NSString).substring(with: NSRange(location: start, length: safeOffset - start))
    }

    private func makeContextSlice(startingAt offset: Int, length: Int) -> String {
        let nsString = flatText as NSString
        guard offset < nsString.length else { return "" }
        let end = min(nsString.length, offset + length)
        return nsString.substring(with: NSRange(location: offset, length: end - offset))
    }
}

/// Weak holder for keeping references to AppKit views in a map without
/// retaining them.
final class WeakRef<T: AnyObject> {
    weak var value: T?
    init(value: T) { self.value = value }
}

extension NSAttributedString.Key {
    /// Marks a persisted-highlight background so we can remove + reapply
    /// cleanly on every update.
    static let jinHighlightID = NSAttributedString.Key("jin.highlight.id")
}
