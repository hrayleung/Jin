import Foundation

extension MarkdownRenderPreparation {
    static func normalizeInlineTable(_ line: String) -> String {
        guard line.contains("|") else { return line }

        var normalized = line

        if let firstPipeIndex = normalized.firstIndex(of: "|") {
            let prefix = normalized[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(normalized[firstPipeIndex...])
            if !prefix.isEmpty, looksLikeTableRow(suffix), !looksLikeParagraphWithPipes(prefix) {
                normalized = String(prefix) + "\n" + suffix
            }
        }

        normalized = replacing(
            pattern: #"(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)\s*(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)"#,
            in: normalized,
            with: "$1\n$2"
        )

        normalized = replacing(
            pattern: #"(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)\s*(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)"#,
            in: normalized,
            with: "$1\n$2"
        )

        return normalized
    }

    static func looksLikeTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"),
              trimmed.hasSuffix("|") else {
            return false
        }

        let cells = tableCells(in: trimmed)
        return cells.count >= 2
    }

    static func lineHasInlineTableBreakage(_ line: String) -> Bool {
        guard line.contains("|") else { return false }

        if let firstPipeIndex = line.firstIndex(of: "|") {
            let prefix = line[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(line[firstPipeIndex...])
            if !prefix.isEmpty, looksLikeTableRow(suffix), !looksLikeParagraphWithPipes(prefix) {
                return true
            }
        }

        if matches(#"(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)\s*(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)"#, in: line) {
            return true
        }

        return matches(#"(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)\s*(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)"#, in: line)
    }

    static func tableCells(in line: String) -> [String] {
        line
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { String($0) }
    }

    static func looksLikeParagraphWithPipes(_ prefix: String) -> Bool {
        prefix.contains(".") || prefix.contains(":") || prefix.contains("：") || prefix.split(separator: " ").count > 5
    }
}
