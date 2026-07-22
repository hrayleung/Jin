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

        // Detect a data-row / separator-row pair with a deterministic cell
        // scan. The former ICU expressions nested multiple lazy repetitions
        // around every pipe. A perfectly valid, wide table row with no match
        // could therefore trigger catastrophic backtracking and hold the raw
        // Markdown placeholder on screen for minutes.
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { splitInlineTableRows(in: String($0)) }
            .joined(separator: "\n")
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

        return inlineTableRowBreakRange(in: line) != nil
    }

    /// Splits one or more table rows that a model emitted on the same source
    /// line. Each pass removes one boundary; the cap protects repair work from
    /// untrusted output containing thousands of deliberately ambiguous empty
    /// cells while still covering far more glued rows than a model normally
    /// produces.
    private static func splitInlineTableRows(in line: String) -> String {
        let maximumSplits = 32
        var pending = [line]
        var output: [String] = []
        var splitCount = 0

        while let candidate = pending.popLast() {
            guard splitCount < maximumSplits,
                  let breakRange = inlineTableRowBreakRange(in: candidate) else {
                output.append(candidate)
                continue
            }

            let left = String(candidate[..<breakRange.lowerBound])
            let right = String(candidate[breakRange.upperBound...])
            // Stack order is reversed so the source-order left segment is
            // processed and emitted first.
            pending.append(right)
            pending.append(left)
            splitCount += 1
        }

        return output.joined(separator: "\n")
    }

    /// Finds the whitespace gap between two adjacent edge pipes when the
    /// cells on exactly one side form a GFM separator row. All prefix/suffix
    /// separator classifications are precomputed, making this O(n) in the
    /// source-line length with no regex backtracking.
    private static func inlineTableRowBreakRange(in line: String) -> Range<String.Index>? {
        guard line.contains("|") else { return nil }

        guard let firstContent = line.firstIndex(where: { !$0.isWhitespace }),
              let lastContent = line.lastIndex(where: { !$0.isWhitespace }),
              line[firstContent] == "|",
              line[lastContent] == "|" else {
            return nil
        }

        var pipeIndices: [String.Index] = []
        var index = firstContent
        while index <= lastContent {
            if line[index] == "|" {
                pipeIndices.append(index)
            }
            guard index < lastContent else { break }
            index = line.index(after: index)
        }

        // Two edge-pipe rows with at least two cells each require six pipes
        // (`|a|b||---|---|`) and five between-pipe segments.
        guard pipeIndices.count >= 6 else { return nil }

        var cells: [Substring] = []
        cells.reserveCapacity(pipeIndices.count - 1)
        for offset in 0..<(pipeIndices.count - 1) {
            let lowerBound = line.index(after: pipeIndices[offset])
            cells.append(line[lowerBound..<pipeIndices[offset + 1]])
        }

        let separatorCells = cells.map(isTableSeparatorCell)
        let dataCells = cells.map { !$0.isEmpty }
        var separatorPrefix = Array(repeating: true, count: cells.count + 1)
        var dataPrefix = Array(repeating: true, count: cells.count + 1)
        for offset in cells.indices {
            separatorPrefix[offset + 1] = separatorPrefix[offset] && separatorCells[offset]
            dataPrefix[offset + 1] = dataPrefix[offset] && dataCells[offset]
        }
        var separatorSuffix = Array(repeating: true, count: cells.count + 1)
        var dataSuffix = Array(repeating: true, count: cells.count + 1)
        for offset in cells.indices.reversed() {
            separatorSuffix[offset] = separatorSuffix[offset + 1] && separatorCells[offset]
            dataSuffix[offset] = dataSuffix[offset + 1] && dataCells[offset]
        }

        for boundaryCell in cells.indices {
            guard cells[boundaryCell].allSatisfy({ $0.isWhitespace }) else { continue }

            let leftCellCount = boundaryCell
            let rightCellCount = cells.count - boundaryCell - 1
            guard leftCellCount >= 2, rightCellCount >= 2 else { continue }

            let leftIsSeparator = separatorPrefix[boundaryCell]
            let rightIsSeparator = separatorSuffix[boundaryCell + 1]
            let leftIsData = dataPrefix[boundaryCell]
            let rightIsData = dataSuffix[boundaryCell + 1]

            guard (leftIsSeparator && rightIsData)
                    || (rightIsSeparator && leftIsData) else {
                continue
            }

            return line.index(after: pipeIndices[boundaryCell])..<pipeIndices[boundaryCell + 1]
        }

        return nil
    }

    private static func isTableSeparatorCell(_ cell: Substring) -> Bool {
        guard var lowerBound = cell.firstIndex(where: { !$0.isWhitespace }),
              let lastContent = cell.lastIndex(where: { !$0.isWhitespace }) else {
            return false
        }
        var upperBound = cell.index(after: lastContent)

        if cell[lowerBound] == ":" {
            lowerBound = cell.index(after: lowerBound)
        }
        guard lowerBound < upperBound else { return false }
        if cell[cell.index(before: upperBound)] == ":" {
            upperBound = cell.index(before: upperBound)
        }
        guard lowerBound < upperBound else { return false }

        let core = cell[lowerBound..<upperBound]
        return core.count >= 3 && core.allSatisfy { $0 == "-" }
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
