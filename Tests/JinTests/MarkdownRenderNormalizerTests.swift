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

        let normalized = MarkdownRenderNormalizer.normalize(input, modelID: "deepseek-v4-flash")

        XCTAssertTrue(normalized.contains("## 5. 🌱 Future of Energy"))
        XCTAssertTrue(normalized.contains("materials\n- Advanced Nuclear Technologies"))
        XCTAssertTrue(normalized.contains("\n---\n"))
        XCTAssertTrue(normalized.contains("## 6. ☁️ Cloud"))
        XCTAssertTrue(normalized.contains("|---|---|"))
        XCTAssertTrue(normalized.contains("Autonomous Systems | Moving from pilots"))
    }

    func testLeavesOtherModelsUnchanged() {
        let input = """
        ##5. Keep exact malformed output
        Text- Not a list---
        |------|-------------|
        """

        XCTAssertEqual(MarkdownRenderNormalizer.normalize(input, modelID: nil), input)
        XCTAssertEqual(MarkdownRenderNormalizer.normalize(input, modelID: "gpt-5"), input)
        XCTAssertEqual(MarkdownRenderNormalizer.normalize(input, modelID: "kimi-k2"), input)
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
}
