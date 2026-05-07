import CoreGraphics
import Foundation

enum CodeExecContentBlockSupport {
    struct Metrics: Equatable {
        let lineCount: Int
        let longestLineLength: Int
        let characterCount: Int
    }

    static func metrics(for text: String) -> Metrics {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return Metrics(
            lineCount: max(lines.count, 1),
            longestLineLength: lines.map(\.count).max() ?? text.count,
            characterCount: text.count
        )
    }

    static func showsExpandControl(for metrics: Metrics) -> Bool {
        metrics.lineCount > 12 || metrics.longestLineLength > 120 || metrics.characterCount > 800
    }

    static func currentMaxHeight(
        for metrics: Metrics,
        isExpanded: Bool,
        collapsedHeight: CGFloat,
        expandedHeight: CGFloat
    ) -> CGFloat? {
        guard showsExpandControl(for: metrics) else { return nil }
        return isExpanded ? expandedHeight : collapsedHeight
    }

    static func lineNumberText(forLineCount lineCount: Int) -> String? {
        guard lineCount > 1, lineCount <= 400 else { return nil }
        return (1...lineCount).map(String.init).joined(separator: "\n")
    }
}
