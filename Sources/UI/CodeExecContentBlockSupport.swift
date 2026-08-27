import Foundation

enum CodeExecContentBlockSupport {
    struct Metrics: Equatable {
        let lineCount: Int
        let longestLineLength: Int
        let characterCount: Int
    }

    /// Collapsed tool cards show this many source lines before "Show more".
    static let collapsedLineLimit = 12
    /// Expanded cards still cap render height so a huge dump cannot blow up
    /// the timeline row. Copy always includes the full original text.
    static let expandedRenderLineLimit = 80

    static func metrics(for text: String) -> Metrics {
        let lines = Self.lines(from: text)
        return Metrics(
            lineCount: max(lines.count, 1),
            longestLineLength: lines.map(\.count).max() ?? text.count,
            characterCount: text.count
        )
    }

    static func showsExpandControl(for metrics: Metrics) -> Bool {
        metrics.lineCount > collapsedLineLimit
    }

    static func visibleText(for text: String, isExpanded: Bool) -> String {
        let allLines = lines(from: text)
        let limit = isExpanded ? expandedRenderLineLimit : collapsedLineLimit
        guard allLines.count > limit else { return text }
        return allLines.prefix(limit).joined(separator: "\n")
    }

    static func hiddenLineCount(for metrics: Metrics, isExpanded: Bool) -> Int {
        let limit = isExpanded ? expandedRenderLineLimit : collapsedLineLimit
        return max(0, metrics.lineCount - limit)
    }

    static func expandControlTitle(hiddenLineCount: Int, isExpanded: Bool) -> String {
        if isExpanded {
            return "Show less"
        }
        return hiddenLineCount == 1 ? "Show 1 more line" : "Show \(hiddenLineCount) more lines"
    }

    static func truncatedRemainderCaption(hiddenLineCount: Int) -> String? {
        guard hiddenLineCount > 0 else { return nil }
        if hiddenLineCount == 1 {
            return "1 more line — copy for the full output"
        }
        return "\(hiddenLineCount) more lines — copy for the full output"
    }

    static func lines(from text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    static func lineNumberText(forLineCount lineCount: Int) -> String? {
        guard lineCount > 1, lineCount <= 400 else { return nil }
        return (1...lineCount).map(String.init).joined(separator: "\n")
    }
}
