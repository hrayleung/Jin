import Foundation

extension MarkdownRenderPreparation {
    static func normalizeInlineTable(_ line: String) -> String {
        guard line.contains("|") else { return line }

        var normalized = line

        if let firstPipeIndex = normalized.firstIndex(of: "|") {
            let prefix = normalized[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(normalized[firstPipeIndex...])
            // Only split prose glued to a classic edge-pipe table. Using the
            // broader no-edge-pipe detector here would treat `方面 | taskset`
            // as "prefix + table" and shatter valid no-edge-pipe rows.
            if !prefix.isEmpty,
               looksLikeEdgePipeTableRow(suffix),
               !looksLikeParagraphWithPipes(prefix) {
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

    /// True for a GFM pipe-table data/separator line, with or without outer
    /// pipes (`| a | b |` and `a | b` both count). Used to keep structural
    /// repairs from inserting mid-row newlines that shatter tables.
    static func looksLikeTableRow(_ line: String) -> Bool {
        looksLikeEdgePipeTableRow(line) || looksLikeNoEdgePipeTableRow(line)
    }

    /// Classic GFM row with leading and trailing `|`.
    static func looksLikeEdgePipeTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"),
              trimmed.hasSuffix("|") else {
            return false
        }
        return tableCells(in: trimmed).count >= 2
    }

    /// GFM rows written without outer pipes (`A | B | C`). Stricter than the
    /// edge-pipe form so prose with incidental `|` is not treated as a table.
    static func looksLikeNoEdgePipeTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else { return false }
        // Already covered by the edge-pipe path; avoid double-counting and
        // accidental acceptance of half-edged rows as "no-edge" forms.
        if trimmed.hasPrefix("|") || trimmed.hasSuffix("|") {
            return false
        }

        // Leading list markers are never table rows for repair purposes.
        if matches(#"^(?:[-*+]|\d{1,2}[.)])\s+"#, in: trimmed) {
            return false
        }

        // Sentence-like / colon-labeled lines → prose, not a compact table row.
        // Do not reuse `looksLikeParagraphWithPipes`'s short word-count gate —
        // multi-column rows often exceed 5 whitespace tokens.
        if trimmed.contains(". ")
            || trimmed.hasSuffix(".")
            || trimmed.contains(":")
            || trimmed.contains("：") {
            return false
        }
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount > 16 {
            return false
        }

        return tableCells(in: trimmed).count >= 2
    }

    static func lineHasInlineTableBreakage(_ line: String) -> Bool {
        guard line.contains("|") else { return false }

        if let firstPipeIndex = line.firstIndex(of: "|") {
            let prefix = line[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(line[firstPipeIndex...])
            if !prefix.isEmpty,
               looksLikeEdgePipeTableRow(suffix),
               !looksLikeParagraphWithPipes(prefix) {
                return true
            }
        }

        if matches(#"(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)\s*(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)"#, in: line) {
            return true
        }

        return matches(#"(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)\s*(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)"#, in: line)
    }

    /// Pipe-delimited cells, tolerating optional outer `|`. Empty edge
    /// segments from leading/trailing pipes are dropped; internal empties
    /// (empty cells) are kept.
    static func tableCells(in line: String) -> [String] {
        var parts = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0) }
        if line.hasPrefix("|"),
           let first = parts.first,
           first.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.removeFirst()
        }
        if line.hasSuffix("|"),
           let last = parts.last,
           last.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.removeLast()
        }
        return parts
    }

    static func looksLikeParagraphWithPipes(_ prefix: String) -> Bool {
        prefix.contains(".") || prefix.contains(":") || prefix.contains("：") || prefix.split(separator: " ").count > 5
    }
}
