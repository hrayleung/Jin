import Foundation

/// Which rows to feed to `NativeMarkdownCache` ahead of the viewport during a
/// user scroll. The conversation-open prewarm only ever covers the window
/// tail, so scrolling UP is the cache-miss direction: a row realizing on a
/// miss mounts a plain-text placeholder, parses off-main, then re-measures —
/// warming it before it enters the viewport removes that double-layout.
enum ChatTimelineScrollPrewarmPlanner {
    static let rowsAbove = 8
    static let rowsBelow = 4
    /// Total item cap per wave — `prewarm` skips already-cached keys, so
    /// repeat waves over warm rows dispatch nothing.
    static let maxItemsPerWave = 12

    /// Row indexes ordered by realize-likelihood: (top−1, top−2, …) then
    /// (bottom+1, bottom+2, …), clamped to `0..<rowCount`, excluding the
    /// visible range itself.
    static func candidateRows(rowCount: Int, visibleRange: Range<Int>) -> [Int] {
        guard rowCount > 0 else { return [] }
        var candidates: [Int] = []
        candidates.reserveCapacity(rowsAbove + rowsBelow)
        for offset in 1...rowsAbove {
            let row = visibleRange.lowerBound - offset
            guard row >= 0 else { break }
            candidates.append(row)
        }
        for offset in 0..<rowsBelow {
            let row = visibleRange.upperBound + offset
            guard row < rowCount else { break }
            candidates.append(row)
        }
        return candidates
    }

    /// Per-message prewarm extraction, shared with the stage view's
    /// conversation-open prewarm (`extractPrewarmItems`) so the render-mode
    /// rules cannot drift between the two callers: assistant-only, collapsed
    /// previews skipped, plain-text flag mirroring the render mode.
    static func prewarmItems(
        for message: MessageRenderItem,
        renderMode: MessageRenderMode
    ) -> [NativeMarkdownCache.PrewarmItem] {
        guard message.isAssistant, renderMode != .collapsedPreview else { return [] }
        let renderPlainText = renderMode == .nativeText

        var items: [NativeMarkdownCache.PrewarmItem] = []
        for block in message.renderedBlocks {
            guard case .content(_, let part) = block else { continue }
            guard case .text(let text) = part, !text.isEmpty else { continue }
            items.append(NativeMarkdownCache.PrewarmItem(
                markdownText: text,
                renderPlainText: renderPlainText
            ))
        }
        return items
    }
}
