import Foundation

extension MarkdownRenderPreparation {
    static func normalizeBlockSpacing(in markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return markdown }

        var output: [String] = []
        output.reserveCapacity(lines.count + 8)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousTrimmed = output.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if shouldInsertBlankLine(before: trimmed, previous: previousTrimmed) {
                output.append("")
            }

            output.append(line)
        }

        return output.joined(separator: "\n")
    }

    static func shouldInsertBlankLine(before current: String, previous: String) -> Bool {
        guard !current.isEmpty, !previous.isEmpty else { return false }

        if isHeadingLine(current) || isThematicBreakLine(current) {
            return !isHeadingLine(previous) && !isThematicBreakLine(previous)
        }

        if isListMarkerLine(current) {
            return !isListMarkerLine(previous)
                && !isHeadingLine(previous)
                && !isThematicBreakLine(previous)
        }

        if looksLikeTableRow(current), !looksLikeTableRow(previous) {
            return !isListMarkerLine(previous)
        }

        return false
    }

    static func isHeadingLine(_ line: String) -> Bool {
        matches(#"^#{1,6}\s+\S"#, in: line)
    }

    static func isThematicBreakLine(_ line: String) -> Bool {
        matches(#"^(?:---+|\*\*\*+|___+)$"#, in: line)
    }

    static func isListMarkerLine(_ line: String) -> Bool {
        matches(#"^(?:[-*+]\s+|\d{1,2}[.)]\s+)"#, in: line)
    }
}
