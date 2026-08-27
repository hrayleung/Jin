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
    /// Wrapping a minified JSON/base64 blob with few newlines can still create
    /// thousands of visual lines. Keep a character cap beside the line cap.
    static let collapsedCharacterLimit = 800
    static let expandedCharacterLimit = 4_000

    static func metrics(for text: String) -> Metrics {
        let lines = Self.lines(from: text)
        return Metrics(
            lineCount: max(lines.count, 1),
            longestLineLength: lines.map(\.count).max() ?? text.count,
            characterCount: text.count
        )
    }

    static func showsExpandControl(for metrics: Metrics) -> Bool {
        isTruncated(metrics: metrics, isExpanded: false)
    }

    static func visibleText(for text: String, isExpanded: Bool) -> String {
        let allLines = lines(from: text)
        let lineLimit = isExpanded ? expandedRenderLineLimit : collapsedLineLimit
        let characterLimit = isExpanded ? expandedCharacterLimit : collapsedCharacterLimit
        let lineLimited = allLines.count > lineLimit
            ? allLines.prefix(lineLimit).joined(separator: "\n")
            : text
        return truncatedToCharacterLimit(lineLimited, limit: characterLimit)
    }

    static func hiddenLineCount(for metrics: Metrics, isExpanded: Bool) -> Int {
        let limit = isExpanded ? expandedRenderLineLimit : collapsedLineLimit
        return max(0, metrics.lineCount - limit)
    }

    static func expandControlTitle(for metrics: Metrics, isExpanded: Bool) -> String {
        if isExpanded {
            return "Show less"
        }
        let hiddenLines = hiddenLineCount(for: metrics, isExpanded: false)
        if hiddenLines == 1 {
            return "Show 1 more line"
        }
        if hiddenLines > 1 {
            return "Show \(hiddenLines) more lines"
        }
        return "Show more"
    }

    static func truncatedRemainderCaption(for metrics: Metrics) -> String? {
        guard isTruncated(metrics: metrics, isExpanded: true) else { return nil }
        let hiddenLines = hiddenLineCount(for: metrics, isExpanded: true)
        if hiddenLines == 1 {
            return "1 more line — copy for the full output"
        }
        if hiddenLines > 1 {
            return "\(hiddenLines) more lines — copy for the full output"
        }
        return "More output — copy for the full output"
    }

    static func lines(from text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    static func lineNumberText(forLineCount lineCount: Int) -> String? {
        guard lineCount > 1, lineCount <= 400 else { return nil }
        return (1...lineCount).map(String.init).joined(separator: "\n")
    }

    static func isTruncated(metrics: Metrics, isExpanded: Bool) -> Bool {
        let lineLimit = isExpanded ? expandedRenderLineLimit : collapsedLineLimit
        let characterLimit = isExpanded ? expandedCharacterLimit : collapsedCharacterLimit
        return metrics.lineCount > lineLimit || metrics.characterCount > characterLimit
    }

    private static func truncatedToCharacterLimit(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}
