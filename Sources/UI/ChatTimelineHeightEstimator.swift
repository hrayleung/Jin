import Foundation

/// Content-aware height estimate for an unmeasured timeline row.
///
/// `heightOfRow` must return a number WITHOUT realizing the cell (the
/// recycling invariant), so off-screen rows are sized from this estimate
/// until they scroll into view and report their real `fittingSize`. The
/// closer the estimate, the smaller the correction delta the scroll-anchor
/// compensation has to absorb when the real height lands. The previous
/// estimate (`chars / (width/8) * 22 + 64`) was blind to CJK (≈2× the
/// column width of Latin) and to content shape (code blocks, headings,
/// tables), so CJK/code-heavy history was estimated 30-50% short — and it
/// re-counted `copyText.count` (O(n)) on EVERY `heightOfRow` call; the
/// controller now memoizes this per (identity, width).
///
/// Constants are tuned against the `estimate_error` diagnostics events
/// (chat-diagnostics ndjson) emitted on each row's first real measurement.
enum ChatTimelineHeightEstimator {
    // Derived from the default theme: 13pt body × 1.3 line-height plus
    // paragraph spacing folded in; 12pt monospaced code lines.
    private static let bodyLineHeight = 23.0
    private static let codeLineHeight = 18.0
    private static let codeBlockChrome = 56.0   // header bar + padding
    private static let headingHeight = 34.0
    private static let tableRowHeight = 30.0
    private static let blankLineSpacing = 6.0
    // Header (~18) + bubble padding (12×2) + footer actions (~22) +
    // VStack spacing/footer top pad (~8) + row vertical padding (8×2).
    // The previous 64 under-counted the footer strip by ~one action-row,
    // so just-sent user rows were pre-seeded short: the copy/regenerate
    // cluster painted into the streaming bubble until the first real
    // measure landed (the "buttons overlap on send" glitch).
    private static let rowChrome = 96.0

    // The chrome strips that `copyText` is structurally blind to
    // (`copyableText` keeps only .text/.quote parts). A search+thinking
    // reply used to open ~480pt short of its real height — the card clipped
    // partway through — purely because the estimate never counted these.
    private static let searchStripHeight = 44.0
    private static let thinkingHeaderHeight = 40.0
    private static let activityRowHeight = 36.0

    /// - Parameter columnWidth: the timeline column width (full message rail).
    /// - Parameter isUser: user bubbles wrap at ~70% of the column; estimating
    ///   against the full width under-counts wraps for long pastes, while a
    ///   stale too-tall cache leaves a clear band under a short bubble. Pass
    ///   the role so the wrap width matches the real bubble.
    /// - Parameters hasSearchActivities/hasThinking/toolChromeRowCount:
    ///   collapsed-chrome strips rendered ABOVE/BELOW the prose that the text
    ///   heuristic cannot see (search summary row, thinking disclosure
    ///   header, MCP tool + code-exec timeline rows).
    static func estimate(
        text: String,
        columnWidth: CGFloat,
        isUser: Bool = false,
        hasSearchActivities: Bool = false,
        hasThinking: Bool = false,
        toolChromeRowCount: Int = 0
    ) -> CGFloat {
        let wrapWidth: CGFloat
        if isUser {
            wrapWidth = ChatConversationLayoutMetrics.userBubbleMaxWidth(for: columnWidth)
        } else {
            wrapWidth = max(1, columnWidth)
        }
        var height = estimateWrapped(text: text, wrapWidth: wrapWidth)
        if hasSearchActivities { height += searchStripHeight }
        if hasThinking { height += thinkingHeaderHeight }
        height += Double(min(toolChromeRowCount, 20)) * activityRowHeight
        return height
    }

    /// Core wrap-aware estimate against an explicit content width.
    static func estimateWrapped(text: String, wrapWidth: CGFloat) -> CGFloat {
        // ~7.5 pt per Latin column at default body size; floor so a zero/unknown
        // width cannot explode the line count into thousands of pixels.
        let columnsPerLine = max(16.0, Double(max(wrapWidth, 160)) / 7.5)
        var height = rowChrome
        var inCodeFence = false
        var lineCount = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineCount += 1
            let trimmed = line.drop(while: { $0 == " " })

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if !inCodeFence { height += codeBlockChrome }
                inCodeFence.toggle()
                continue
            }
            if inCodeFence {
                height += codeLineHeight
                continue
            }
            if trimmed.isEmpty {
                height += blankLineSpacing
                continue
            }
            if trimmed.first == "#" {
                height += headingHeight
                continue
            }
            if trimmed.first == "|" {
                height += tableRowHeight
                continue
            }

            var columns = 0.0
            for scalar in line.unicodeScalars {
                columns += isWideScalar(scalar) ? 2.0 : 1.0
            }
            height += max(1.0, (columns / columnsPerLine).rounded(.up)) * bodyLineHeight
        }

        // Guard against pathological pastes producing multi-viewport estimates
        // that paint a clear band under a short first-measure host before the
        // real fittingSize lands. Cap is generous (~3× a tall laptop viewport).
        let capped = min(height, 4_000.0 + Double(min(lineCount, 200)) * 4.0)

        // Short user turns still need the full chrome (header + footer).
        return CGFloat(max(capped, rowChrome))
    }

    /// East-Asian-wide scalar ranges: these occupy ≈2 Latin columns.
    private static func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x1100...0x115F).contains(v)
            || (0x2E80...0x303E).contains(v)
            || (0x3041...0x33FF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x4E00...0x9FFF).contains(v)
            || (0xA000...0xA4CF).contains(v)
            || (0xAC00...0xD7A3).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0xFE30...0xFE4F).contains(v)
            || (0xFF00...0xFF60).contains(v)
            || (0x20000...0x2FFFD).contains(v)
    }
}
