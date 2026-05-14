import XCTest
@testable import Jin

final class MarkdownRenderPreparationTests: XCTestCase {
    func testRepairsScreenshotStyleHeadingsListsRulesAndInlineTable() {
        let input = """
        Here are the top news headlines for **April24,2026**:
        ### 🌍 World / Geopolitics- **U.S.–Iran Tensions:** President Trump has ordered U.S. forces to respond.
        - **Iranian Response:** Mojtaba Khamenei dismissed reports.
        ---
        ## 🇮🇳 India- **Politics:** The BJP has hit back at Rahul Gandhi.
        🔗 Cross-Cutting Themes| Theme | Description |
        |------|-------------|| Autonomous Systems | Moving from pilots |
        """

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.diagnostics.repairMode, .repaired)
        XCTAssertLessThanOrEqual(result.diagnostics.anomalyScoreAfter, result.diagnostics.anomalyScoreBefore)
        XCTAssertTrue(result.text.contains("### 🌍 World / Geopolitics\n- **U.S.–Iran Tensions:**"))
        XCTAssertTrue(result.text.contains("## 🇮🇳 India\n- **Politics:**"))
        XCTAssertTrue(result.text.contains("🔗 Cross-Cutting Themes\n\n| Theme | Description |"))
        XCTAssertTrue(result.text.contains("|------|-------------|\n| Autonomous Systems | Moving from pilots |"))
    }

    func testRepairsContentDetectedAnomaliesWithoutModelID() {
        let input = """
        ##5. Keep exact malformed output
        Text- Not a list---
        |------|-------------|
        """

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.diagnostics.repairMode, .repaired)
        XCTAssertTrue(result.text.contains("## 5. Keep exact malformed output"))
        XCTAssertTrue(result.text.contains("Text\n\n- Not a list"))
        XCTAssertTrue(result.text.contains("\n---\n"))
    }

    func testLeavesValidMarkdownUnchanged() {
        let input = """
        ## Valid heading

        - First item
        - Second item

        | Theme | Description |
        | --- | --- |
        | Autonomous Systems | Moving from pilots |
        """

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.diagnostics.repairMode, .none)
        XCTAssertEqual(result.text, input)
    }

    func testUnescapesLeadingEmphasisInUnicodeBulletLists() {
        let input = """
        • \\*Iran talks / Middle East:\\*
        The White House says talks may happen.

        • \\*\\*Markets:\\*\\*
        Stocks hit records.
        """

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertTrue(result.didChange)
        XCTAssertLessThan(result.diagnostics.anomalyScoreAfter, result.diagnostics.anomalyScoreBefore)
        XCTAssertTrue(result.text.contains("• *Iran talks / Middle East:*"))
        XCTAssertTrue(result.text.contains("• **Markets:**"))
    }

    func testDoesNotRewriteModelTextQualityIssues() {
        let input = "The result was announced on April24,2026, involved of30 billion rupees, and mentioned age92."

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotUnescapeEscapedEmphasisInsideInlineCode() {
        let input = "Use `\\*literal\\*` when explaining escaped emphasis."

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotNormalizeInsideFencedCodeBlocks() {
        let input = """
        ```markdown
        ##5. Keep literal- Not a list---
        |------|-------------|
        ```
        ##6. Fix this
        """

        let normalized = MarkdownRenderPreparation.prepare(input)

        XCTAssertTrue(normalized.contains("##5. Keep literal- Not a list---"))
        XCTAssertTrue(normalized.contains("|------|-------------|"))
        XCTAssertTrue(normalized.contains("## 6. Fix this"))
    }

    func testMixedFenceDelimiterInsideCodeBlockDoesNotEndProtection() {
        let input = """
        ```markdown
        ~~~
        ##5. Keep literal- Not a list---
        ```
        ##6. Fix this
        """

        let normalized = MarkdownRenderPreparation.prepare(input)

        XCTAssertTrue(normalized.contains("##5. Keep literal- Not a list---"))
        XCTAssertTrue(normalized.contains("## 6. Fix this"))
    }

    func testLongerFenceRequiresMatchingLengthClosingFence() {
        let input = """
        ````markdown
        ```swift
        ##5. Keep literal- Not a list---
        ```
        ````
        ##6. Fix this
        """

        let normalized = MarkdownRenderPreparation.prepare(input)

        XCTAssertTrue(normalized.contains("##5. Keep literal- Not a list---"))
        XCTAssertTrue(normalized.contains("## 6. Fix this"))
    }

    func testDoesNotNormalizeInsideDisplayMathBlocks() {
        let input = """
        $$
        ##5. Keep literal- Not a list---
        $$
        ##6. Fix this
        """

        let normalized = MarkdownRenderPreparation.prepare(input)

        XCTAssertTrue(normalized.contains("##5. Keep literal- Not a list---"))
        XCTAssertTrue(normalized.contains("## 6. Fix this"))
    }

    func testStreamingPreparationDoesNotDependOnHardBreakPreference() {
        let input = """
        ##7. Cloud & AI InfrastructureToken costs have dropped.
        Strategic hybrid cloud- cloud for elasticity
        """

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)

        XCTAssertTrue(result.didChange)
        XCTAssertTrue(result.text.contains("## 7. Cloud & AI Infrastructure\nToken costs have dropped."))
        XCTAssertTrue(result.text.contains("Strategic hybrid cloud\n- cloud for elasticity"))
    }

    func testLeavesOrdinaryPipeTextUnchanged() {
        let input = "This paragraph talks about CLI | REST API | MCP Server usage without a table."

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    // MARK: - Screenshot regression: italic must not turn into a fake bullet

    func testDoesNotBreakValidItalicIntoBulletStreaming() {
        let input = "That said... yeah, there *is* some naivety here."
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertEqual(result.text, input, "italic *is* must survive intact")
        XCTAssertFalse(result.text.contains("\n* "))
    }

    func testDoesNotBreakValidItalicIntoBulletFinal() {
        let input = "That said... yeah, there *is* some naivety here."
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotBreakValidWillItalic() {
        let input = "But you *will* be if you keep letting it control your happiness."
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertEqual(result.text, input)
    }

    func testStillBreaksGenuineEmbeddedDashBullets() {
        // Real malformed: `Apples- bananas- cherries` should still split into
        // bullets — this regex transform must keep working for non-emphasis
        // candidates. Block-spacing then inserts a blank line before the
        // first list item.
        let input = "Fruits include apples- bananas- cherries"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertTrue(result.didChange)
        XCTAssertTrue(result.text.contains("apples\n\n- bananas"))
        XCTAssertTrue(result.text.contains("- bananas\n- cherries"))
    }

    // MARK: - Streaming completion: auto-close unclosed inline markers

    func testClosesUnclosedItalicAtParagraphEnd() {
        let input = "*hello\n\nworld"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertEqual(result.text, "*hello*\n\nworld")
    }

    func testClosesUnclosedBoldAtParagraphEnd() {
        let input = "**hello\n\nworld"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertEqual(result.text, "**hello**\n\nworld")
    }

    func testClosesUnclosedItalicAtEndOfStream() {
        // Mid-stream: trailing unclosed `*` gets closed for stable display.
        let input = "The next *step"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertEqual(result.text, "The next *step*")
    }

    func testClosesUnclosedFenceAtEndOfStream() {
        let input = "Here is code:\n```python\nprint(1)"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertTrue(result.text.hasSuffix("\n```"), "expected closing fence appended; got: \(result.text)")
        XCTAssertTrue(result.text.contains("```python\nprint(1)"))
    }

    func testDoesNotCloseInsideValidMultilineEmphasis() {
        // Soft-break inside one paragraph: emphasis is balanced; no synthetic close.
        let input = "*line1\nline2*"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertEqual(result.text, input)
    }

    func testStreamingMidEmphasisIsClosedOnEveryContentPrefix() {
        // After the `*` is followed by at least one non-whitespace character,
        // every subsequent streaming prefix must render with the italic auto-
        // closed (mainstream LLM-chat behavior — no flashing literal `*`).
        let full = "The next *step* is clear."
        let openIdx = full.firstIndex(of: "*")!
        let firstContentIdx = full.index(after: openIdx)
        let lengths = stride(
            from: full.distance(from: full.startIndex, to: firstContentIdx) + 1,
            through: full.count,
            by: 1
        )
        for length in lengths {
            let prefix = String(full.prefix(length))
            let result = MarkdownRenderPreparation.prepareForRender(prefix, isStreaming: true)
            let asterisks = result.text.filter { $0 == "*" }.count
            XCTAssertEqual(
                asterisks % 2,
                0,
                "prefix \(prefix.debugDescription) → \(result.text.debugDescription) has unbalanced *"
            )
        }
    }

    func testIntraWordUnderscoreIsNotMistakenForEmphasis() {
        // `snake_case_thing` must not trigger any repair or completion.
        let input = "Use snake_case_thing for variable names."
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testInlineCodeWithAsterisksIsLeftAlone() {
        let input = "Use `*foo*` literally to mean the literal asterisks."
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testCleanProseIsBypassedEntirely() {
        let input = "Yeah, maybe a little.\n\nBut not in the way you think."
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    // MARK: - Smushed `**bold title**` at end of heading line

    func testSplitsSmushedBoldTitleInH2WithEmojiPrefix() {
        let input = "## 🌍 Major Stories**Trump-Xi Summit in Beijing**"

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.diagnostics.repairMode, .repaired)
        XCTAssertLessThan(result.diagnostics.anomalyScoreAfter, result.diagnostics.anomalyScoreBefore)
        XCTAssertTrue(result.text.contains("## 🌍 Major Stories\n**Trump-Xi Summit in Beijing**"))
    }

    func testSplitsSmushedBoldTitleAcrossMultipleSectionsScreenshotInput() {
        let input = """
        ## 🌍 Major Stories**Trump-Xi Summit in Beijing**
        President Trump is meeting with Xi Jinping in Beijing.

        **China Gains Edge on U.S. Amid Iran War**
        A confidential U.S. intelligence assessment circulating during the trip.

        ## 🏛️ U.S. News**Alex Murdaugh Convictions Overturned**
        The South Carolina Supreme Court overturned the murder convictions.

        ## 🌐 International**Kyiv Under Attack**
        Russian missiles and drones pounded Kyiv overnight.
        """

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertTrue(result.didChange)
        XCTAssertTrue(result.text.contains("## 🌍 Major Stories\n**Trump-Xi Summit in Beijing**"))
        XCTAssertTrue(result.text.contains("## 🏛️ U.S. News\n**Alex Murdaugh Convictions Overturned**"))
        XCTAssertTrue(result.text.contains("## 🌐 International\n**Kyiv Under Attack**"))
        // Already-correct subsection titles must not be duplicated or mangled.
        let correctOccurrences = result.text.components(separatedBy: "**China Gains Edge on U.S. Amid Iran War**").count - 1
        XCTAssertEqual(correctOccurrences, 1)
    }

    func testSplitsSmushedBoldTitleWhileStreaming() {
        let input = "## 🌍 Major Stories**Trump-Xi Summit in Beijing**"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertTrue(result.text.contains("## 🌍 Major Stories\n**Trump-Xi Summit in Beijing**"))
    }

    func testSplitsSmushedBoldTitleAtOtherHeadingLevels() {
        let h1Input = "# Top Section**Multi Word Subtitle Here**"
        let h1Result = MarkdownRenderPreparation.prepareForRender(h1Input, isStreaming: false)
        XCTAssertTrue(h1Result.text.contains("# Top Section\n**Multi Word Subtitle Here**"))

        let h3Input = "### Sub Section**Multi Word Subtitle Here**"
        let h3Result = MarkdownRenderPreparation.prepareForRender(h3Input, isStreaming: false)
        XCTAssertTrue(h3Result.text.contains("### Sub Section\n**Multi Word Subtitle Here**"))
    }

    func testDoesNotSplitHeadingWithSpacedBoldFollowedByPunctuation() {
        let input = "## Welcome to **Jin**!"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotSplitHeadingWithSpacedBoldReference() {
        let input = "## See **Section 3.2 for details**"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotSplitHeadingStartingWithBold() {
        let input = "## **Important multi word**: update available"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotSplitShortBoldAbbreviation() {
        let input = "## Note**TODO**"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotSplitSmushedSingleWordBold() {
        let input = "## Section**Subtitle**"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotSplitWhenBoldNotAtEndOfLine() {
        let input = "## Section**Bold word here**More text after"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotSplitStreamingPartialBeforeClosingMarkers() {
        // Closing `**` hasn't arrived yet — the detector requires it at end
        // of line, so during streaming the smushed heading stays as one line
        // until the next chunk fills in the close.
        let input = "## 🌍 Major Stories**Trump-Xi Summit in Beij"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertFalse(result.text.contains("## 🌍 Major Stories\n**"))
    }

    func testStreamingUnclosedBoldHeadingStillGetsSyntheticClose() {
        let input = "## Foo**Bar Baz"

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.text, "## Foo**Bar Baz**")
    }

    func testDoesNotSplitEscapedSmushedBoldMarkerInHeading() {
        let input = #"## Title\**not bold text**"#

        let finalResult = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertFalse(finalResult.didChange)
        XCTAssertEqual(finalResult.text, input)

        let streamingResult = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)
        XCTAssertFalse(streamingResult.didChange)
        XCTAssertEqual(streamingResult.text, input)
    }

    func testDoesNotSplitBoldInsideInlineCode() {
        let input = "## Use `**foo bar baz**` literally"
        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }
}
