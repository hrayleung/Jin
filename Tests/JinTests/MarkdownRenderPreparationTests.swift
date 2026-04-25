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
}
