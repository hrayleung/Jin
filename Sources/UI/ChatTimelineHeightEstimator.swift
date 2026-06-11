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
    private static let rowChrome = 64.0          // bubble padding + header/footer

    static func estimate(text: String, columnWidth: CGFloat) -> CGFloat {
        let columnsPerLine = max(16.0, Double(columnWidth) / 7.5)
        var height = rowChrome
        var inCodeFence = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
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

        return CGFloat(max(height, 44))
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
