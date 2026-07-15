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
            normalized = insertZeroWidthSpaceAtCJKEmphasisBoundary(normalized)
            normalized = insertBreakBetweenHeadingAndBody(normalized)
            normalized = insertBreakBeforeSmushedBoldTitleInHeading(normalized)
            return normalized
        }
    }

    // MARK: - Emphasis-aware transforms

    /// Computes inline-emphasis & inline-code ranges ONCE for the line, then
    /// applies every break-insertion transform through a helper that skips
    /// regex matches whose range overlaps protected spans. Ranges are only
    /// recomputed when a transform actually changed the string (the
    /// tokenizer retokenizes the line, previously up to 6× per line even
    /// when nothing changed); each transform also has a cheap character
    /// pre-flight so lines without its trigger characters skip the regex.
    private static func applyEmphasisAwareTransforms(_ line: String) -> String {
        var current = line
        var ranges = protectedRanges(in: current)

        func apply(_ transform: (String, [Range<String.Index>]) -> String) {
            let next = transform(current, ranges)
            if next != current {
                current = next
                ranges = protectedRanges(in: current)
            }
        }

        apply(insertBreaksBeforeEmbeddedHorizontalRules)
        apply(insertBreaksBeforeEmbeddedHeadings)
        apply(insertBreaksBeforeEmbeddedBullets)
        apply(insertBreaksBeforeEmbeddedOrderedListMarkers)
        apply(insertBreaksBeforeEmbeddedOrderedListMarkerInHeading)
        apply(normalizeInlineTable)
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

    static func insertBreaksBeforeEmbeddedHorizontalRules(
        _ line: String,
        _ ranges: [Range<String.Index>]
    ) -> String {
        guard line.contains("---") else { return line }
        return MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(?<!^)(?<!\n)(?<!-)(---+)(?=(?:#{1,6}\S| {0,3}[-*+]\s|$))"#,
            in: line,
            protectedRanges: ranges,
            with: "\n$1\n"
        )
    }

    static func insertBreaksBeforeEmbeddedHeadings(
        _ line: String,
        _ ranges: [Range<String.Index>]
    ) -> String {
        guard line.contains("###") else { return line }
        var current = line
        current = MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: embeddedHeadingAfterWhitespacePattern,
            in: current,
            protectedRanges: ranges,
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
            protectedRanges: current == line ? ranges : protectedRanges(in: current),
            with: "$1\n$2 "
        )
        return current
    }

    static func insertBreaksBeforeEmbeddedBullets(
        _ line: String,
        _ ranges: [Range<String.Index>]
    ) -> String {
        // Intact GFM table rows must stay on one line. Cell text often has
        // operator-like `+`/`-` after CJK closers (`（NUMA）+ 更多策略`) that
        // match the bullet pattern below; inserting a newline shatters the
        // row, ends the table early, and dumps the rest as pipe prose.
        if MarkdownRenderPreparation.looksLikeTableRow(line) { return line }

        // Two lookbehinds keep a marker that isn't really a bullet literal:
        //   `(?<!\\)` — an escaped `A\*`/`\-` (the model meant a literal `*`,
        //     common inside table cells); splitting it shatters the table row.
        //   `(?<!\d)` — a marker glued to a digit is a count/range/operator,
        //     not a list marker: `每年 600+ 篇`, `5-10 个` must not become bullets.
        // Genuine glued bullets follow a letter or CJK punctuation
        // (`Geopolitics- **U.S.**`), so neither guard touches them.
        guard line.contains("-") || line.contains("*") || line.contains("+") else { return line }
        return MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(?<=\S)(?<![*+-])(?<!\\)(?<!\d)([-*+])\s+(?=(?:\*\*)?[\p{L}\p{N}])"#,
            in: line,
            protectedRanges: ranges,
            with: "\n$1 "
        )
    }

    static func insertBreaksBeforeEmbeddedOrderedListMarkers(
        _ line: String,
        _ ranges: [Range<String.Index>]
    ) -> String {
        // Same shatter risk as bullets: cells like `| 步骤 | 1. 初始化 |`
        // must not gain a mid-row newline before the ordered marker.
        if MarkdownRenderPreparation.looksLikeTableRow(line) { return line }
        guard line.rangeOfCharacter(from: .decimalDigits) != nil else { return line }
        return MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(?<=[\.:：;；\)])\s*(\d{1,2}[.)])\s+(?=[\p{L}\p{N}])"#,
            in: line,
            protectedRanges: ranges,
            with: "\n$1 "
        )
    }

    /// Heading-only variant: when the current line is an ATX heading and the
    /// model glued an ordered-list marker directly to a Han character (e.g.
    /// `## 三、投资风格与持仓特点1. **极度集中**…`), split before the marker. The
    /// general-purpose `insertBreaksBeforeEmbeddedOrderedListMarkers` requires
    /// preceding ASCII/CJK punctuation, which Chinese titles don't have, so
    /// this fills the gap without loosening the broader paragraph rule.
    static func insertBreaksBeforeEmbeddedOrderedListMarkerInHeading(
        _ line: String,
        _ ranges: [Range<String.Index>]
    ) -> String {
        guard line.contains("#") else { return line }
        guard let newlineIndex = line.firstIndex(of: "\n") else {
            return insertBreaksBeforeEmbeddedOrderedListMarkerInSingleHeadingLine(line, ranges)
        }

        // The heading sub-line is a different string from the caller's, so
        // its protected ranges must be computed for it specifically.
        let headingLine = String(line[..<newlineIndex])
        let remainder = String(line[newlineIndex...])
        return insertBreaksBeforeEmbeddedOrderedListMarkerInSingleHeadingLine(
            headingLine,
            protectedRanges(in: headingLine)
        ) + remainder
    }

    private static func insertBreaksBeforeEmbeddedOrderedListMarkerInSingleHeadingLine(
        _ line: String,
        _ ranges: [Range<String.Index>]
    ) -> String {
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
            protectedRanges: ranges,
            with: "$1\n$2 "
        )
    }

    // MARK: - CJK emphasis boundary fix

    /// Inserts a zero-width space (U+200B) at `**` boundaries that
    /// CommonMark's flanking rules would otherwise reject, so the LLM-
    /// common pattern `**...（SIAC）**对` renders as bold instead of
    /// falling through to literal asterisks.
    ///
    /// **Background**: CommonMark §6.2 requires a closing `**` to be
    /// right-flanking — and when the character immediately before `**`
    /// is a Unicode punctuation, the rule additionally demands the
    /// character immediately after `**` be whitespace or punctuation.
    /// CJK text frequently violates this:
    /// `**新加坡国际仲裁中心（SIAC）**对` puts the closing `**` between
    /// `）` (punctuation) and `对` (letter), the spec rejects it, and
    /// swift-markdown surfaces the whole run as a single literal text
    /// node with the `**` markers showing through.
    ///
    /// A zero-width space placed just before that closing `**` makes
    /// the run "preceded by a letter" from CommonMark's perspective —
    /// the visible glyph sequence is unchanged but the parser now
    /// happily produces a `Strong` node. The symmetric case (opening
    /// `**` between letter and punctuation, e.g. `他**——副标题**`) is
    /// handled by inserting the ZWSP after the opening `**` instead.
    ///
    /// The ZWSP is invisible when rendered and harmless when copied;
    /// we picked it over a regular space because a real space would
    /// change the visible output, which is the very thing this fix
    /// avoids.
    /// The flanking failure this repair targets is a *CJK* phenomenon —
    /// CommonMark's rule only bites when CJK punctuation/ideographs sit on
    /// the emphasis boundary. Each pattern therefore requires a CJK
    /// character on at least one side. An unrestricted `\p{P}` version
    /// previously fired on Latin text like `f(x)**2 … g(y)**3`, made the
    /// two `**` runs flank, and the parser swallowed the literal asterisks
    /// into a bogus bold span.
    private static let cjkLetterClass = #"\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}"#
    private static let cjkPunctuationClass =
        "（）「」『』【】〈〉《》〔〕［］｛｝、，。；：！？…・～｜—％"

    static func insertZeroWidthSpaceAtCJKEmphasisBoundary(_ line: String) -> String {
        guard line.contains("*") else { return line }
        let zwsp = "\u{200B}"
        let cjkL = cjkLetterClass
        let cjkP = NSRegularExpression.escapedPattern(for: cjkPunctuationClass)
        var result = line

        // Closing-`**` failure: punctuation + `**` + letter/digit.
        // Insert ZWSP between the punctuation and the `**`.
        // (a) CJK punctuation before the `**`; any letter after.
        result = MarkdownRenderPreparation.replacing(
            pattern: "([\(cjkP)])(\\*\\*)(?=[\\p{L}\\p{N}])",
            in: result,
            with: "$1\(zwsp)$2"
        )
        // (b) Any punctuation before; CJK letter after. (ZWSP inserted by
        // (a) is category Cf, not P, so the two variants never double-fire.)
        result = MarkdownRenderPreparation.replacing(
            pattern: "(\\p{P})(\\*\\*)(?=[\(cjkL)])",
            in: result,
            with: "$1\(zwsp)$2"
        )

        // Opening-`**` failure: letter/digit + `**` + punctuation.
        // Insert ZWSP between the `**` and the punctuation. CJK letters are
        // captured (not look-behind) because `\p{Han}` is variable-width in
        // UTF-16 — Extension B ideographs are surrogate pairs.
        result = MarkdownRenderPreparation.replacing(
            pattern: "([\(cjkL)])(\\*\\*)(\\p{P})(?=[^\\n]*\\*\\*)",
            in: result,
            with: "$1$2\(zwsp)$3"
        )
        result = MarkdownRenderPreparation.replacing(
            pattern: "(?<=[\\p{L}\\p{N}])(\\*\\*)([\(cjkP)])(?=[^\\n]*\\*\\*)",
            in: result,
            with: "$1\(zwsp)$2"
        )

        // Same pairs for single-`*` (italic) emphasis, but only when not
        // adjacent to another `*` (i.e., not part of `**`).
        result = MarkdownRenderPreparation.replacing(
            pattern: "([\(cjkP)])(?<!\\*)(\\*)(?!\\*)(?=[\\p{L}\\p{N}])",
            in: result,
            with: "$1\(zwsp)$2"
        )
        result = MarkdownRenderPreparation.replacing(
            pattern: "(\\p{P})(?<!\\*)(\\*)(?!\\*)(?=[\(cjkL)])",
            in: result,
            with: "$1\(zwsp)$2"
        )
        result = MarkdownRenderPreparation.replacing(
            pattern: "([\(cjkL)])(?<!\\*)(\\*)(?!\\*)(\\p{P})(?=[^\\n]*(?<!\\*)\\*(?!\\*))",
            in: result,
            with: "$1$2\(zwsp)$3"
        )
        result = MarkdownRenderPreparation.replacing(
            pattern: "(?<=[\\p{L}\\p{N}])(?<!\\*)(\\*)(?!\\*)([\(cjkP)])(?=[^\\n]*(?<!\\*)\\*(?!\\*))",
            in: result,
            with: "$1\(zwsp)$2"
        )
        return result
    }

    // MARK: - Escaped emphasis (unchanged behavior)

    static func unescapeEscapedLeadingEmphasis(_ line: String) -> String {
        guard line.contains(#"\*"#) else { return line }
        var normalized = line
        for marker in ["***", "**", "*"] {
            // Two-step: the LINE-LEADING pattern gates (a line whose start
            // exhibits the broken model habit of escaping intended
            // emphasis); once gated, the relaxed pattern unescapes EVERY
            // whitespace-preceded run on that line — previously only the
            // first run was repaired (`\*\*A\*\* 与 \*\*B\*\*` left the
            // second literal). Ungated lines keep their escapes: prose like
            // `输入 \*斜体\* 即可` means literal asterisks.
            guard MarkdownRenderPreparation.matches(
                escapedLeadingEmphasisPattern(for: marker),
                in: normalized
            ) else { continue }
            normalized = MarkdownRenderPreparation.replacing(
                pattern: escapedAnywhereEmphasisPattern(for: marker),
                in: normalized,
                with: "$1\(marker)$2\(marker)"
            )
        }
        return normalized
    }

    static func hasEscapedLeadingEmphasis(in line: String) -> Bool {
        guard line.contains(#"\*"#) else { return false }
        return ["***", "**", "*"].contains { marker in
            MarkdownRenderPreparation.matches(escapedLeadingEmphasisPattern(for: marker), in: line)
        }
    }

    static func escapedLeadingEmphasisPattern(for marker: String) -> String {
        // Line-leading (including sub-lines earlier repairs created by
        // inserting `\n` into the logical line).
        escapedEmphasisPattern(for: marker, anchor: #"(?:^|(?<=\n))"#)
    }

    static func escapedAnywhereEmphasisPattern(for marker: String) -> String {
        // After any whitespace — used only on lines the leading pattern
        // already gated.
        escapedEmphasisPattern(for: marker, anchor: #"(?:^|(?<=\s))"#)
    }

    private static func escapedEmphasisPattern(for marker: String, anchor: String) -> String {
        let escapedMarker = escapedEmphasisMarkerSequence(for: marker)
        return anchor
            + #"(\s*(?:(?:[-*+•]|\d{1,2}[.)])\s+)?)"#
            + escapedMarker
            + #"(?=\S)([^\n]*?\S)"#
            + escapedMarker
            + #"(?=\s|$|[.,:;!?，。；：、）\)])"#
    }

    static func escapedEmphasisMarkerSequence(for marker: String) -> String {
        String(repeating: #"\\\*"#, count: marker.count)
    }

    // MARK: - Inline table (delegates to existing helpers, then guarded by emphasis ranges)

    static func normalizeInlineTable(
        _ line: String,
        _ ranges: [Range<String.Index>]
    ) -> String {
        guard line.contains("|") else { return line }
        // Tables almost never appear inside emphasis runs; we still use the
        // emphasis-aware helper for the regex-based steps so the rare case
        // of `*foo | bar*` doesn't get rewritten.

        var normalized = line
        var currentRanges = ranges
        if let firstPipeIndex = normalized.firstIndex(of: "|"),
           !currentRanges.contains(where: { $0.contains(firstPipeIndex) }) {
            let prefix = normalized[..<firstPipeIndex].trimmingCharacters(in: .whitespaces)
            let suffix = String(normalized[firstPipeIndex...])
            if !prefix.isEmpty,
               MarkdownRenderPreparation.looksLikeTableRow(suffix),
               !MarkdownRenderPreparation.looksLikeParagraphWithPipes(prefix) {
                normalized = String(prefix) + "\n" + suffix
                currentRanges = protectedRanges(in: normalized)
            }
        }

        var next = MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)\s*(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)"#,
            in: normalized,
            protectedRanges: currentRanges,
            with: "$1\n$2"
        )
        if next != normalized {
            normalized = next
            currentRanges = protectedRanges(in: normalized)
        }

        next = MarkdownRenderPreparation.replacingOutsideRanges(
            pattern: #"(\|\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|)\s*(\|\s*[^|\n]+?\s*(?:\|\s*[^|\n]+?\s*)+\|)"#,
            in: next,
            protectedRanges: currentRanges,
            with: "$1\n$2"
        )

        return next
    }

    // MARK: - Heading body camelCase split (unchanged behavior)

    static func insertBreakBetweenHeadingAndBody(_ line: String) -> String {
        guard line.contains("#") else { return line }
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
                if prefixCount >= 8,
                   suffixCount >= 8,
                   !looksLikeCompactCamelCaseTerm(content: content, at: index),
                   !looksLikeMultiHumpIdentifier(content: content, at: index),
                   !looksLikeContinuedNounPhrase(content: content, at: index) {
                    return index
                }
            }

            previousCharacter = currentCharacter
            index = nextIndex
        }

        return nil
    }

    /// Rejects splits inside compact camelCase/PascalCase terms such as
    /// `GitHub`, `YouTube`, `JavaScript`, `MacBook`, and `MaxLinear`.
    /// Those often appear in headings followed by CJK or English nouns, and
    /// treating their internal case boundary as "heading ended, body starts"
    /// renders half the term as a heading and the rest as a paragraph.
    private static func looksLikeCompactCamelCaseTerm(
        content: Substring,
        at boundaryIndex: Substring.Index
    ) -> Bool {
        var tokenStart = boundaryIndex
        while tokenStart > content.startIndex {
            let previous = content.index(before: tokenStart)
            guard isCompactTermCharacter(content[previous]) else { break }
            tokenStart = previous
        }

        let leftSegmentLength = content.distance(from: tokenStart, to: boundaryIndex)
        return (1...4).contains(leftSegmentLength)
    }

    /// Rejects splits inside multi-hump PascalCase identifiers such as
    /// `MarkdownRenderPreparation` (2 humps) — code symbols routinely appear
    /// in headings (`## MarkdownRenderPreparation 模块详解`) and must not be
    /// torn into heading + fake body. The compact-term guard only protects
    /// left segments of 1-4 chars, which long identifiers exceed. A single
    /// hump (`InfrastructureToken sentence…`) still splits — that's the real
    /// glued-heading-body shape this repair exists for.
    private static func looksLikeMultiHumpIdentifier(
        content: Substring,
        at boundaryIndex: Substring.Index
    ) -> Bool {
        var tokenStart = boundaryIndex
        while tokenStart > content.startIndex {
            let previous = content.index(before: tokenStart)
            guard isCompactTermCharacter(content[previous]) else { break }
            tokenStart = previous
        }
        var tokenEnd = boundaryIndex
        while tokenEnd < content.endIndex, isCompactTermCharacter(content[tokenEnd]) {
            tokenEnd = content.index(after: tokenEnd)
        }

        var transitions = 0
        var previous: Character?
        for character in content[tokenStart..<tokenEnd] {
            if let previous,
               MarkdownRenderPreparation.isLowercaseLetter(previous)
                   || MarkdownRenderPreparation.isDecimalDigit(previous),
               MarkdownRenderPreparation.isUppercaseLetter(character) {
                transitions += 1
                if transitions >= 2 { return true }
            }
            previous = character
        }
        return false
    }

    private static func isCompactTermCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value)
        }
    }

    /// Heuristic guard: rejects camelCase-boundary splits that fall inside
    /// what's clearly an English noun phrase continuation rather than a
    /// glued-on body sentence.
    ///
    /// The original "heading body camelCase split" was designed to recover
    /// from LLM output like `## HeadingTextBody sentence...` — a real
    /// heading concatenated with a real body. But the same `lower → Upper
    /// → lower` pattern is the foundation of every compound English noun
    /// (`MaxLinear`, `OpenAI`, `JavaScript`, `iPhone`, `MacBook`,
    /// `YouTube`, `SwiftUI`) and we were splitting all of them in half
    /// inside headings.
    ///
    /// Real glued-on body text reads like a sentence — the first space-
    /// delimited token after the camelCase boundary contains plain text,
    /// not `,`/`.`/`(`/`（`. Continued noun phrases like `MaxLinear,
    /// Inc.` and `MaxLinear (NASDAQ: MXL)` always do.
    private static func looksLikeContinuedNounPhrase(
        content: Substring,
        at boundaryIndex: Substring.Index
    ) -> Bool {
        let firstTokenEnd = content[boundaryIndex...].firstIndex { char in
            char.isWhitespace
        } ?? content.endIndex
        let firstToken = content[boundaryIndex..<firstTokenEnd]
        for char in firstToken {
            switch char {
            case ",", ".", "(", "[", "（", "［", "、":
                return true
            default:
                continue
            }
        }
        return false
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
        guard line.contains("#"), line.contains("*") else { return nil }
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
                guard !startsWithPunctuation(boldContent) else { return nil }

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

    private static func startsWithPunctuation(_ string: String) -> Bool {
        for scalar in string.unicodeScalars {
            if scalar.value == 0x200B || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            return CharacterSet.punctuationCharacters.contains(scalar)
        }
        return false
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
