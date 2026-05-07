import Foundation

extension MarkdownRenderPreparation {
    static func anomalyScore(in markdown: String) -> Int {
        var score = 0

        _ = transformOutsideProtectedBlocks(in: markdown) { line in
            let protectedLine = preserveInlineCode(in: line) { $0 }

            if matches(#"^( {0,3}#{1,6})(?=\S)"#, in: protectedLine) {
                score += 3
            }
            if matches(#"(?<=\S)\s+(#{1,6})(?=[#\dA-Za-z\p{Han}])"#, in: protectedLine) {
                score += 2
            }
            if matches(#"(?<=\S)(?<![*+-])(?:-\s+(?=(?:\*\*)?[\p{L}\p{N}])|\*\s+(?=[\p{L}\p{N}])|\+\s+(?=[\p{L}\p{N}]))"#, in: protectedLine) {
                score += 2
            }
            if matches(#"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#, in: protectedLine) {
                score += 1
            }
            if MarkdownStructuralRepair.hasEscapedLeadingEmphasis(in: protectedLine) {
                score += 1
            }
            if matches(#"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#, in: protectedLine) {
                score += 2
            }
            if lineHasInlineTableBreakage(protectedLine) {
                score += 2
            }
            if MarkdownStructuralRepair.headingBodySplitIndex(in: protectedLine) != nil {
                score += 1
            }

            return protectedLine
        }

        score += unclosedInlineSignal(in: markdown)

        return score
    }

    /// Counts paragraphs with unmatched inline emphasis markers and adds 1 if a
    /// fenced code block is still open at end of input. Used to open the
    /// `repair` gate so `MarkdownInlineCompletion` can run.
    private static func unclosedInlineSignal(in markdown: String) -> Int {
        var score = 0
        var paragraph: [String] = []
        var fenceMarker: Character?
        var fenceLength = 0
        var insideDisplayMath = false

        func flush() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: "\n")
            if !MarkdownInlineTokenizer.unmatchedMarkers(in: joined).isEmpty {
                score += 1
            }
            paragraph.removeAll(keepingCapacity: true)
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
            let trimmedFull = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let marker = fenceMarker {
                if trimmedLeading.first == marker {
                    let len = trimmedLeading.prefix(while: { $0 == marker }).count
                    if len >= fenceLength,
                       trimmedLeading.dropFirst(len).allSatisfy({ $0 == " " || $0 == "\t" }) {
                        fenceMarker = nil
                        fenceLength = 0
                    }
                }
                continue
            }

            if trimmedFull == "$$" || trimmedFull == "\\[" || trimmedFull == "\\]" {
                flush()
                insideDisplayMath.toggle()
                continue
            }
            if insideDisplayMath {
                continue
            }

            if let first = trimmedLeading.first, first == "`" || first == "~" {
                let len = trimmedLeading.prefix(while: { $0 == first }).count
                if len >= 3 {
                    flush()
                    fenceMarker = first
                    fenceLength = len
                    continue
                }
            }

            if trimmedLeading.hasPrefix("<") || trimmedLeading.hasPrefix("<!--") {
                flush()
                continue
            }

            if trimmedLeading.isEmpty {
                flush()
                continue
            }

            paragraph.append(line)
        }

        flush()

        if fenceMarker != nil {
            score += 1
        }

        return score
    }
}
