import Foundation

extension MarkdownRenderPreparation {
    static func anomalyScore(
        in markdown: String,
        ignoringSmushedBoldTitleInHeading: Bool = false
    ) -> Int {
        var score = 0

        _ = transformOutsideProtectedBlocks(in: markdown) { line in
            // Capture the SANITIZED form (inline code replaced by
            // placeholders) — `preserveInlineCode(in:) { $0 }` restores the
            // code before returning, so its return value would feed code
            // content straight into the score regexes below.
            var protectedLine = line
            _ = preserveInlineCode(in: line) { sanitized in
                protectedLine = sanitized
                return sanitized
            }

            // Cheap character pre-flights gate every regex below — most
            // lines of a normal document contain none of the trigger
            // characters and skip the ICU matching entirely.
            let hasHash = protectedLine.contains("#")
            let hasDigit = protectedLine.rangeOfCharacter(from: .decimalDigits) != nil
            let hasBulletChar = protectedLine.contains("-")
                || protectedLine.contains("*")
                || protectedLine.contains("+")

            // Atomic group on `#{1,6}` so the regex can't backtrack to a
            // shorter prefix. Without it, `## 二、…` (well-formed) would still
            // match: greedy `##` fails lookahead `\S` (next char is space), but
            // backtracks to a single `#` and finds the second `#` as `\S`,
            // generating a false anomaly that breaks the score guard whenever
            // a repair splits one heading into two heading lines.
            if hasHash, matches(#"^( {0,3}(?>#{1,6}))(?=\S)"#, in: protectedLine) {
                score += 3
            }
            if protectedLine.contains("###") {
                if matches(MarkdownStructuralRepair.embeddedHeadingAfterWhitespacePattern, in: protectedLine) {
                    score += 2
                }
                if matches(MarkdownStructuralRepair.cjkEmbeddedHeadingPattern, in: protectedLine) {
                    score += 2
                }
            }
            // Mirror the `(?<!\\)`/`(?<!\d)` guards in
            // `insertBreaksBeforeEmbeddedBullets`: escaped markers and
            // digit-glued `+`/`-` (`600+ 篇`) are not bullets, so they must
            // not score as anomalies and open the repair gate.
            if hasBulletChar, matches(#"(?<=\S)(?<![*+-])(?<!\\)(?<!\d)(?:-\s+(?=(?:\*\*)?[\p{L}\p{N}])|\*\s+(?=[\p{L}\p{N}])|\+\s+(?=[\p{L}\p{N}]))"#, in: protectedLine) {
                score += 2
            }
            if hasDigit, matches(#"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#, in: protectedLine) {
                score += 1
            }
            if hasHash, hasDigit, matches(#"^ {0,3}#{1,6} .*\p{Han}\d{1,2}[.)]\s+(?:\*\*)?[\p{L}\p{N}]"#, in: protectedLine) {
                score += 1
            }
            if MarkdownStructuralRepair.hasEscapedLeadingEmphasis(in: protectedLine) {
                score += 1
            }
            if protectedLine.contains("---"), matches(#"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#, in: protectedLine) {
                score += 2
            }
            if lineHasInlineTableBreakage(protectedLine) {
                score += 2
            }
            if hasHash, MarkdownStructuralRepair.headingBodySplitIndex(in: protectedLine) != nil {
                score += 1
            }
            if !ignoringSmushedBoldTitleInHeading,
               hasHash,
               protectedLine.contains("*"),
               MarkdownStructuralRepair.hasSmushedBoldTitleInHeading(in: protectedLine) {
                score += 2
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
        var displayMathDelimiter: MarkdownDisplayMathDelimiters.Delimiter?

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

            if let delimiter = displayMathDelimiter {
                if case .closes = MarkdownDisplayMathDelimiters.closingRole(
                    ofTrimmedLine: trimmedFull,
                    delimiter: delimiter
                ) {
                    displayMathDelimiter = nil
                }
                continue
            }
            switch MarkdownDisplayMathDelimiters.openingRole(ofTrimmedLine: trimmedFull) {
            case .selfContained:
                flush()
                continue
            case .opens(let delimiter, _):
                flush()
                displayMathDelimiter = delimiter
                continue
            case .none:
                break
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
