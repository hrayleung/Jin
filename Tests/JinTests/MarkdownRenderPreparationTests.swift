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
}
