import XCTest
@testable import Jin

final class MarkdownRenderNormalizerTests: XCTestCase {
    func testNormalizesMalformedHeadingsRulesBulletsAndInlineTableForDeepSeekV4() {
        let input = """
        ##5. 🌱 Future of Energy & SustainabilityThe highest investment trend.
        - Structural Battery Composites — Weight-bearing materials- Advanced Nuclear Technologies — SMRs---
        ##6. ☁️ Cloud & Edge ComputingInvestment remains strong.
        🔗 Cross-Cutting Themes| Theme | Description |
        |------|-------------|| Autonomous Systems | Moving from pilots |
        """

        let result = MarkdownRenderNormalizer.normalizeForRender(
            input,
            modelID: "deepseek-v4-flash",
            isStreaming: false
        )

        XCTAssertTrue(result.didChange)
        XCTAssertNotEqual(result.repairMode, .none)
        XCTAssertLessThan(result.anomalyScoreAfter, result.anomalyScoreBefore)
        XCTAssertTrue(result.text.contains("## 5. 🌱 Future of Energy"))
        XCTAssertTrue(result.text.contains("materials\n- Advanced Nuclear Technologies"))
        XCTAssertTrue(result.text.contains("\n---\n"))
        XCTAssertTrue(result.text.contains("## 6. ☁️ Cloud & Edge Computing\nInvestment remains strong."))
        XCTAssertTrue(result.text.contains("|------|-------------|"))
        XCTAssertTrue(result.text.contains("| Autonomous Systems | Moving from pilots |"))
    }

    func testRepairsAnomalousMarkdownForUnlistedModelsViaContentDetection() {
        let input = """
        ##5. Keep exact malformed output
        Text- Not a list---
        |------|-------------|
        """

        let result = MarkdownRenderNormalizer.normalizeForRender(
            input,
            modelID: "gpt-5",
            isStreaming: false
        )

        XCTAssertTrue(result.didChange)
        XCTAssertNotEqual(result.repairMode, .none)
        XCTAssertLessThan(result.anomalyScoreAfter, result.anomalyScoreBefore)
        XCTAssertTrue(result.text.contains("## 5. Keep exact malformed output"))
        XCTAssertTrue(result.text.contains("Text\n- Not a list"))
        XCTAssertTrue(result.text.contains("\n---\n"))
        XCTAssertTrue(result.text.contains("|------|-------------|"))
    }

    func testLeavesAlreadyValidMarkdownUnchangedForUnrelatedModels() {
        let input = """
        ## Valid heading

        - First item
        - Second item

        | Theme | Description |
        | --- | --- |
        | Autonomous Systems | Moving from pilots |
        """

        let result = MarkdownRenderNormalizer.normalizeForRender(
            input,
            modelID: "gpt-5",
            isStreaming: false
        )

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.repairMode, .none)
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

        let normalized = MarkdownRenderNormalizer.normalize(input, modelID: "deepseek-v4-pro")

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

        let normalized = MarkdownRenderNormalizer.normalize(input, modelID: "deepseek-v4-flash")

        XCTAssertTrue(normalized.contains("##5. Keep literal- Not a list---"))
        XCTAssertTrue(normalized.contains("## 6. Fix this"))
    }

    func testStreamingRepairPrefersHardBreaksForExactKimiModelIDs() {
        let input = """
        ##7. ☁️ Cloud & AI InfrastructureToken costs have dropped 280-fold in two years.
        Strategic hybrid cloud- cloud for elasticity
        """

        let result = MarkdownRenderNormalizer.normalizeForRender(
            input,
            modelID: "@cf/moonshotai/kimi-k2.6",
            isStreaming: true
        )

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.repairMode, .safe)
        XCTAssertTrue(result.preferHardBreaks)
        XCTAssertTrue(result.text.contains("## 7. ☁️ Cloud & AI Infrastructure"))
        XCTAssertTrue(result.text.contains("Strategic hybrid cloud\n- cloud for elasticity"))
    }
}
