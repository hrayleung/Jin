import XCTest
@testable import Jin

final class MarkdownInlineTokenizerTests: XCTestCase {
    // MARK: - Basic emphasis pairing

    func testPairsSingleAsterisk() {
        let input = "before *foo* after"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(extract(input, ranges[0]), "*foo*")
    }

    func testPairsDoubleAsterisk() {
        let input = "before **foo** after"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertFalse(ranges.isEmpty)
        XCTAssertTrue(ranges.contains { extract(input, $0) == "**foo**" })
    }

    func testPairsTripleAsterisk() {
        let input = "x ***foo*** y"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertFalse(ranges.isEmpty)
        XCTAssertTrue(ranges.contains { extract(input, $0) == "***foo***" })
    }

    // MARK: - Screenshot bug regression: closing-asterisk recognition

    func testClosingAsteriskOfItalicIsRecognized() {
        // The exact failure mode from the screenshot: the closing `*` of `*is*`
        // must be inside an emphasis range so MarkdownStructuralRepair will
        // skip it and not insert `\n* ` after it.
        let input = "yeah, there *is* some naivety here."
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(extract(input, ranges[0]), "*is*")
    }

    func testWillEmphasisIsRecognized() {
        let input = "But you *will* be if you keep letting it control your happiness."
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(extract(input, ranges[0]), "*will*")
    }

    // MARK: - Unmatched markers

    func testUnclosedSingleAsterisk() {
        let input = "*foo"
        let unmatched = MarkdownInlineTokenizer.unmatchedMarkers(in: input)
        XCTAssertEqual(unmatched.count, 1)
        XCTAssertEqual(unmatched[0].marker, "*")
    }

    func testUnclosedDoubleAsteriskReportsTwoSingles() {
        // ** unclosed — reported as 2 single `*` unmatched markers; the
        // completion pass concatenates them which yields the same `**` closer.
        let input = "**foo"
        let unmatched = MarkdownInlineTokenizer.unmatchedMarkers(in: input)
        XCTAssertEqual(unmatched.count, 2)
        XCTAssertTrue(unmatched.allSatisfy { $0.marker == "*" })
    }

    func testCleanInputHasNoUnmatched() {
        let input = "this is *clean* and **also clean** prose"
        let unmatched = MarkdownInlineTokenizer.unmatchedMarkers(in: input)
        XCTAssertTrue(unmatched.isEmpty)
    }

    func testCloserOnlyAsteriskIsNotReportedAsUnmatched() {
        // `she said.*` — `*` is preceded by punctuation, followed by EOF/space.
        // Right-flanking only; cannot be repaired by appending another `*`.
        let input = "she said.*"
        let unmatched = MarkdownInlineTokenizer.unmatchedMarkers(in: input)
        XCTAssertTrue(unmatched.isEmpty, "closer-only `*` must not be auto-closed; got \(unmatched)")
    }

    func testTrailingStandaloneAsteriskIsNotUnmatched() {
        // `foo *` — `*` preceded by space, followed by EOF. Neither flanking;
        // not a valid emphasis delimiter, so completion leaves it alone.
        let input = "foo *"
        let unmatched = MarkdownInlineTokenizer.unmatchedMarkers(in: input)
        XCTAssertTrue(unmatched.isEmpty)
    }

    // MARK: - Underscore intra-word exclusion

    func testIntraWordUnderscoreIsNotEmphasis() {
        let input = "snake_case_thing is identifier"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertTrue(ranges.isEmpty)

        let unmatched = MarkdownInlineTokenizer.unmatchedMarkers(in: input)
        XCTAssertTrue(unmatched.isEmpty, "Intra-word `_` is neither emphasis nor unmatched")
    }

    func testWordBoundaryUnderscoreEmphasisStillPairs() {
        let input = "before _foo_ after"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(extract(input, ranges[0]), "_foo_")
    }

    // MARK: - Backslash escapes

    func testEscapedAsteriskDoesNotPair() {
        let input = "this has \\*literal\\* asterisks"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertTrue(ranges.isEmpty)
    }

    // MARK: - Inline code

    func testInlineCodeProtectsAsterisks() {
        let input = "use `*foo*` literally"
        let tokens = MarkdownInlineTokenizer.tokenize(input)
        let codeTokens = tokens.compactMap { token -> Range<String.Index>? in
            if case .inlineCode(let range) = token { return range }
            return nil
        }
        XCTAssertEqual(codeTokens.count, 1)
        XCTAssertEqual(extract(input, codeTokens[0]), "`*foo*`")

        // The `*foo*` inside backticks should NOT be reported as emphasis.
        let emphasisRanges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        // emphasisRanges includes inline code, so we filter by overlap with code.
        let onlyEmphasis = emphasisRanges.filter { range in
            !codeTokens.contains(where: { $0.contains(range.lowerBound) })
        }
        XCTAssertTrue(onlyEmphasis.isEmpty)
    }

    func testNestedBackticksWithDifferentRunLengths() {
        // ``foo `bar` baz`` — inner ` ` ` is part of code content, outer ``...`` pairs.
        let input = "x ``foo `bar` baz`` y"
        let tokens = MarkdownInlineTokenizer.tokenize(input)
        let codeTokens = tokens.compactMap { token -> Range<String.Index>? in
            if case .inlineCode(let range) = token { return range }
            return nil
        }
        XCTAssertEqual(codeTokens.count, 1)
        XCTAssertEqual(extract(input, codeTokens[0]), "``foo `bar` baz``")
    }

    // MARK: - Strikethrough

    func testTildeStrikethroughPairs() {
        let input = "before ~~foo~~ after"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(extract(input, ranges[0]), "~~foo~~")
    }

    func testSingleTildeIsNotEmphasis() {
        let input = "approx ~5 minutes"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertTrue(ranges.isEmpty)
    }

    // MARK: - Multi-line emphasis

    func testEmphasisAcrossSoftBreakIsRecognized() {
        let input = "*line1\nline2*"
        let ranges = MarkdownInlineTokenizer.emphasisRanges(in: input)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(extract(input, ranges[0]), "*line1\nline2*")
    }

    // MARK: - Helpers

    private func extract(_ input: String, _ range: Range<String.Index>) -> String {
        String(input[range])
    }
}
