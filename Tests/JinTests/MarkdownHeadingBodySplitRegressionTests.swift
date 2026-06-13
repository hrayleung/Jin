import XCTest
@testable import Jin

final class MarkdownHeadingBodySplitRegressionTests: XCTestCase {
    func testDoesNotSplitGitHubInsideHeading() {
        let input = "## 2. 公开 GitHub 证据：有，但不算很硬"

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotSplitGitHubInsideCJKGluedHeading() {
        let input = "## 2. 公开GitHub证据：有，但不算很硬"

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testDoesNotSplitCommonCompactCamelCaseTermsInsideHeading() {
        let input = "## Compare GitHub JavaScript YouTube MacBook and MaxLinear examples"

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.text, input)
    }

    func testStillSplitsClearlyGluedHeadingBodySentence() {
        let input = "##7. Cloud & AI InfrastructureToken costs have dropped."

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: true)

        XCTAssertTrue(result.didChange)
        XCTAssertTrue(result.text.contains("## 7. Cloud & AI Infrastructure\nToken costs have dropped."))
    }

    func testDoesNotSplitMultiHumpIdentifierInHeading() {
        // ≥2 lower→Upper transitions in the token = a code symbol, not a
        // glued heading+body. `MarkdownRenderPreparation` must stay intact.
        let input = "## MarkdownRenderPreparation 模块详解"

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertEqual(result.text, input, "multi-hump identifier was split: \(result.text.debugDescription)")
    }

    func testDoesNotSplitMultiHumpIdentifierMidHeadingSentence() {
        let input = "## Understanding the NativeMarkdownGroupBuilder aggregation rules in detail"

        let result = MarkdownRenderPreparation.prepareForRender(input, isStreaming: false)

        XCTAssertEqual(result.text, input)
    }
}
