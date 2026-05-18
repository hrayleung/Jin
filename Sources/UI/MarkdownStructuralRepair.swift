import Foundation

/// Per-line structural repairs that reshape malformed model output (heading
/// concatenations, embedded bullets, inline tables…) into something
/// markdown-it can parse correctly. Replaces the prior regex-only pipeline
/// in `MarkdownRenderPreparation+LineRepair.swift`; every break-insertion
/// step is now guarded against firing inside matched inline emphasis or
/// inline code, so legitimate `*foo*` and `**bar**` runs survive untouched.
enum MarkdownStructuralRepair {
    static let embeddedHeadingAfterWhitespacePattern = #"(?<=\S)\s+(#{3,6})(?!#)(?=[\p{L}\p{N}])"#
    static let cjkEmbeddedHeadingPattern = #"([\p{Han}。！？，、：；）」』】])(#{3,6})(?!#)(?=[\p{L}\p{N}])"#

    static func repairLine(_ line: String) -> String {
        MarkdownRenderPreparation.preserveInlineCode(in: line) { candidate in
            var normalized = candidate
            normalized = normalizeHeadingSpacing(normalized)
            normalized = applyEmphasisAwareTransforms(normalized)
            normalized = unescapeEscapedLeadingEmphasis(normalized)
            normalized = insertBreakBetweenHeadingAndBody(normalized)
            normalized = insertBreakBeforeSmushedBoldTitleInHeading(normalized)
            return normalized
        }
    }

    // MARK: - Emphasis-aware transforms

    /// Computes inline-emphasis & inline-code ranges once for the line, then
    /// applies every break-insertion transform through a helper that skips
    /// regex matches whose range overlaps protected spans.
    private static func applyEmphasisAwareTransforms(_ line: String) -> String {
        var current = line
        // Emphasis ranges must be recomputed when the string content changes
        // (table normalization can split a line by inserting `\n`). Each
        // transform calls `protectedRanges(in: current)` afresh.
        current = insertBreaksBeforeEmbeddedHorizontalRules(current)
        current = insertBreaksBeforeEmbeddedHeadings(current)
        current = insertBreaksBeforeEmbeddedBullets(current)
        current = insertBreaksBeforeEmbeddedOrderedListMarkers(current)
        current = insertBreaksBeforeEmbeddedOrderedListMarkerInHeading(current)
        current = normalizeInlineTable(current)
        return current
    }

    private static func protectedRanges(in line: String) -> [Range<String.Index>] {
        MarkdownInlineTokenizer.emphasisRanges(in: line)
    }

    // MARK: - Heading spacing (unchanged behavior)

    static func normalizeHeadingSpacing(_ line: String) -> String {
        let leadingWhitespaceCount = line.prefix(while: { $0 == " " }).count
        guard leadingWhitespaceCount <= 3 else { return line }

        let contentStart = line.index(line.startIndex, offsetBy: leadingWhitespaceCount)
        var hashIndex = contentStart
        var hashCount = 0

        while hashIndex < line.endIndex, line[hashIndex] == "#", hashCount < 7 {
            hashCount += 1
            hashIndex = line.index(after: hashIndex)
        }

        guard (1...6).contains(hashCount), hashIndex < line.endIndex else { return line }
        guard line[hashIndex] != " ", line[hashIndex] != "\t" else { return line }

        let leadingWhitespace = String(line[..<contentStart])
        let headingMarker = String(repeating: "#", count: hashCount)
        let remainder = line[hashIndex...]
        return leadingWhitespace + headingMarker + " " + remainder
    }

    // MARK: - Break insertions (emphasis-aware)

    static func insertBreaksBeforeEmbeddedHorizontalRules(_ line: String) -> String {
        MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#,
            in: line,
            protectedRanges: protectedRanges(in: line),
            with: "\n$1\n"
        )
    }

    static func insertBreaksBeforeEmbeddedHeadings(_ line: String) -> String {
        var current = line
        current = MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: embeddedHeadingAfterWhitespacePattern,
            in: current,
            protectedRanges: protectedRanges(in: current),
            with: "\n$1 "
        )
        // CJK-glued embedded heading: `战役###1.早期…` (no whitespace before the
        // `#`). `\p{Han}` in lookbehind would be variable-width in UTF-16
        // (Extension B chars are surrogate pairs), so capture the preceding
        // char instead and re-emit it. Set is restricted to Han + CJK punctuation
        // so version strings (`C#####foo`) and Latin tail (`Baz##Heading`) are
        // untouched. Require `###` or deeper because inline `##` tokens are
        // common in prose (for example C macro token-pasting). Trailing space
        // ensures the new line parses as a proper ATX heading without re-running
        // `normalizeHeadingSpacing`.
        current = MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: cjkEmbeddedHeadingPattern,
            in: current,
            protectedRanges: protectedRanges(in: current),
            with: "$1\n$2 "
        )
        return current
    }

    static func insertBreaksBeforeEmbeddedBullets(_ line: String) -> String {
        MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(?<=\S)(?<![*+-])([-*+])\s+(?=(?:\*\*)?[\p{L}\p{N}])"#,
            in: line,
            protectedRanges: protectedRanges(in: line),
            with: "\n$1 "
        )
    }

    static func insertBreaksBeforeEmbeddedOrderedListMarkers(_ line: String) -> String {
        MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#,
            in: line,
            protectedRanges: protectedRanges(in: line),
            with: "\n$1 "
        )
    }

    /// Heading-only variant: when the current line is an ATX heading and the
    /// model glued an ordered-list marker directly to a Han character (e.g.
    /// `## 三、投资风格与持仓特点1. **极度集中**…`), split before the marker. The
    /// general-purpose `insertBreaksBeforeEmbeddedOrderedListMarkers` requires
    /// preceding ASCII/CJK punctuation, which Chinese titles don't have, so
    /// this fills the gap without loosening the broader paragraph rule.
    static func insertBreaksBeforeEmbeddedOrderedListMarkerInHeading(_ line: String) -> String {
        guard let newlineIndex = line.firstIndex(of: "\n") else {
            return insertBreaksBeforeEmbeddedOrderedListMarkerInSingleHeadingLine(line)
        }

        let headingLine = String(line[..<newlineIndex])
        let remainder = String(line[newlineIndex...])
        return insertBreaksBeforeEmbeddedOrderedListMarkerInSingleHeadingLine(headingLine) + remainder
    }

    private static func insertBreaksBeforeEmbeddedOrderedListMarkerInSingleHeadingLine(_ line: String) -> String {
        let trimmedLeading = String(line.drop(while: { $0 == " " }))
        guard MarkdownRenderPreparation.matches(#"^#{1,6} "#, in: trimmedLeading) else {
            return line
        }
        // Capture the preceding Han char rather than using `(?<=\p{Han})` —
        // see the comment in `insertBreaksBeforeEmbeddedHeadings` for the
        // surrogate-pair lookbehind rationale.
        return MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(\p{Han})(\d{1,2}[.)])\s+(?=(?:\*\*)?[\p{L}\p{N}])"#,
            in: line,
            protectedRanges: protectedRanges(in: line),
            with: "$1\n$2 "
        )
    }

    // MARK: - Escaped emphasis (unchanged behavior)

    static func unescapeEscapedLeadingEmphasis(_ line: String) -> String {
        var normalized = line
        for marker in ["***", "**", "*"] {
            normalized = MarkdownRenderPreparation.replacing(
                pattern: escapedLeadingEmphasisPattern(for: marker),
                in: normalized,
                with: "$1\(marker)$2\(marker)"
            )
        }
        return normalized
    }

    static func hasEscapedLeadingEmphasis(in line: String) -> Bool {
        ["***", "**", "*"].contains { marker in
            MarkdownRenderPreparation.matches(escapedLeadingEmphasisPattern(for: marker), in: line)
        }
    }

    static func escapedLeadingEmphasisPattern(for marker: String) -> String {
        let escapedMarker = escapedEmphasisMarkerSequence(for: marker)
        return #"^(\s*(?:(?:[-*+•]|\d{1,2}[.)])\s+)?)"#
            + escapedMarker
            + #"(?=\S)([^\n]*?\S)"#
            + escapedMarker
            + #"(?=\s|$|[.,:;!?，。；：、）\)])"#
    }

    static func escapedEmphasisMarkerSequence(for marker: String) -> String {
        String(repeating: #"\\\*"#, count: marker.count)
    }

    // MARK: - Inline table (delegates to existing helpers, then guarded by emphasis ranges)

    static func normalizeInlineTable(_ line: String) -> String {
        guard line.contains("|") else { return line }
        // Tables almost never appear inside emphasis runs; we still use the
        // emphasis-aware helper for the regex-based steps so the rare case
        // of `*foo | bar*` doesn't get rewritten.

        let ranges = protectedRanges(in: line)

        var normalized = line
        if let firstPipeIndex = normalized.firstIndex(of: "|"),
           !ranges.contains(where: { $0.contains(firstPipeIndex) }) {
            let prefix = normalized[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(normalized[firstPipeIndex...])
            if !prefix.isEmpty,
               MarkdownRenderPreparation.looksLikeTableRow(suffix),
               !MarkdownRenderPreparation.looksLikeParagraphWithPipes(prefix) {
                normalized = String(prefix) + "\n" + suffix
            }
        }

        normalized = MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)\s*(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)"#,
            in: normalized,
            protectedRanges: protectedRanges(in: normalized),
            with: "$1\n$2"
        )

        normalized = MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)\s*(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)"#,
            in: normalized,
            protectedRanges: protectedRanges(in: normalized),
            with: "$1\n$2"
        )

        return normalized
    }

    // MARK: - Heading body camelCase split (unchanged behavior)

    static func insertBreakBetweenHeadingAndBody(_ line: String) -> String {
        let leadingWhitespace = String(line.prefix { $0.isWhitespace })
        let trimmedLeading = String(line.dropFirst(leadingWhitespace.count)).trimmingCharacters(in: .whitespaces)
        guard MarkdownRenderPreparation.matches(#"^#{1,6}\s+"#, in: trimmedLeading),
              let splitIndex = headingBodySplitIndex(in: trimmedLeading) else {
            return line
        }

        let before = trimmedLeading[..<splitIndex].trimmingCharacters(in: .whitespaces)
        let after = trimmedLeading[splitIndex...].trimmingCharacters(in: .whitespaces)
        guard !before.isEmpty, !after.isEmpty else { return line }

        return leadingWhitespace + before + "\n" + after
    }

    static func headingBodySplitIndex(in line: String) -> String.Index? {
        let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
        guard let headingMatch = MarkdownRenderPreparation.firstMatch(
            pattern: #"^#{1,6}\s+"#,
            in: trimmedLeading
        ) else { return nil }

        guard let headingRange = Range(headingMatch.range, in: trimmedLeading) else { return nil }
        let content = trimmedLeading[headingRange.upperBound...]
        guard content.count >= 16 else { return nil }

        var previousCharacter: Character?
        var index = content.startIndex

        while index < content.endIndex {
            let currentCharacter = content[index]
            let nextIndex = content.index(after: index)
            let nextCharacter = nextIndex < content.endIndex ? content[nextIndex] : nil

            if let previousCharacter,
               MarkdownRenderPreparation.isLowercaseLetter(previousCharacter) || MarkdownRenderPreparation.isDecimalDigit(previousCharacter),
               MarkdownRenderPreparation.isUppercaseLetter(currentCharacter),
               nextCharacter.map(MarkdownRenderPreparation.isLowercaseLetter) == true {
                let prefixCount = content.distance(from: content.startIndex, to: index)
                let suffixCount = content.distance(from: index, to: content.endIndex)
                if prefixCount >= 8, suffixCount >= 8 {
                    return index
                }
            }

            previousCharacter = currentCharacter
            index = nextIndex
        }

        return nil
    }

    // MARK: - Smushed `**bold title**` at end of heading line

    /// Result of detecting a smushed `**bold title**` run at the end of a
    /// heading line. Carries everything needed to rewrite the line as a
    /// heading followed by a bold-paragraph line.
    struct SmushedBoldTitleHit: Equatable {
        let leadingWhitespace: String
        let headingMarker: String   // includes the trailing space, e.g. "## "
        let prefix: String          // body before the opening `**`
        let boldContent: String     // content between the `**` markers
    }

    /// Detects malformed model output of the form
    /// `## Heading text**Bold subtitle**` — a heading line ending with a
    /// `**...**` run whose opening `**` is glued directly to the preceding
    /// non-whitespace character. Returns `nil` if the line is not a heading,
    /// the `**...**` is not at end of line, the opening is space-separated,
    /// the bold content contains a stray `*`, or substance guards fail.
    static func detectSmushedBoldTitleInHeading(_ line: String) -> SmushedBoldTitleHit? {
        // If an earlier per-line repair already inserted a `\n` into this
        // logical line (camelCase split, embedded bullet, etc.), the heading
        // has already been restructured — leave it alone.
        guard !line.contains("\n") else { return nil }
        let leadingCount = line.prefix(while: { $0 == " " }).count
        guard leadingCount <= 3 else { return nil }
        let leading = String(line.prefix(leadingCount))
        let afterLeading = String(line.dropFirst(leadingCount))

        guard let markerMatch = MarkdownRenderPreparation.firstMatch(
            pattern: #"^#{1,6} "#,
            in: afterLeading
        ), let markerRange = Range(markerMatch.range, in: afterLeading) else { return nil }
        let headingMarker = String(afterLeading[markerRange])
        let bodyChars = Array(afterLeading[markerRange.upperBound...])

        var endIndex = bodyChars.count
        while endIndex > 0, bodyChars[endIndex - 1].isWhitespace {
            endIndex -= 1
        }
        guard endIndex >= 4,
              bodyChars[endIndex - 1] == "*",
              bodyChars[endIndex - 2] == "*" else { return nil }
        let closingStart = endIndex - 2
        guard !isEscaped(in: bodyChars, at: closingStart) else { return nil }

        var i = closingStart - 1
        while i >= 0 {
            if bodyChars[i] == "*" {
                guard i > 0, bodyChars[i - 1] == "*" else { return nil }
                let openingStart = i - 1
                guard openingStart > 0 else { return nil }
                guard !isEscaped(in: bodyChars, at: openingStart) else { return nil }
                let priorChar = bodyChars[openingStart - 1]
                guard !priorChar.isWhitespace, priorChar != "*" else { return nil }

                let prefix = String(bodyChars[0..<openingStart])
                let boldContent = String(bodyChars[(openingStart + 2)..<closingStart])

                guard prefix.count >= 2 else { return nil }
                guard boldContent.count >= 6,
                      boldContent.contains(where: { $0.isWhitespace }) else { return nil }

                return SmushedBoldTitleHit(
                    leadingWhitespace: leading,
                    headingMarker: headingMarker,
                    prefix: prefix,
                    boldContent: boldContent
                )
            }
            i -= 1
        }
        return nil
    }

    static func hasSmushedBoldTitleInHeading(in line: String) -> Bool {
        detectSmushedBoldTitleInHeading(line) != nil
    }

    static func insertBreakBeforeSmushedBoldTitleInHeading(_ line: String) -> String {
        guard let hit = detectSmushedBoldTitleInHeading(line) else { return line }
        return hit.leadingWhitespace + hit.headingMarker + hit.prefix
            + "\n**" + hit.boldContent + "**"
    }

    private static func isEscaped(in characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return false }

        var backslashCount = 0
        var currentIndex = index - 1
        while currentIndex >= 0, characters[currentIndex] == "\\" {
            backslashCount += 1
            currentIndex -= 1
        }

        return backslashCount % 2 == 1
    }
}
