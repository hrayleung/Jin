import XCTest
@testable import Jin

/// Sanity bounds for the content-aware row-height estimator. These assert
/// RELATIVE behavior (CJK wider than Latin, code blocks priced per line,
/// monotonic growth), not absolute pixel values — absolutes are tuned via
/// the `estimate_error` diagnostics.
final class ChatTimelineHeightEstimatorTests: XCTestCase {
    private let width: CGFloat = 700

    func testCJKEstimatesTallerThanSameCountLatin() {
        let latin = String(repeating: "a", count: 400)
        let cjk = String(repeating: "汉", count: 400)
        let latinHeight = ChatTimelineHeightEstimator.estimate(text: latin, columnWidth: width)
        let cjkHeight = ChatTimelineHeightEstimator.estimate(text: cjk, columnWidth: width)
        // Wide scalars ≈2× Latin columns; shared row chrome dilutes the ratio
        // on absolute heights, so assert a clear separation rather than 1.5×.
        XCTAssertGreaterThan(cjkHeight, latinHeight)
        XCTAssertGreaterThan(cjkHeight - latinHeight, 80)
    }

    func testCodeFenceAddsPerLineHeight() {
        let prose = "介绍一下"
        let withCode = prose + "\n```swift\n" + Array(repeating: "let x = 1", count: 30).joined(separator: "\n") + "\n```"
        let delta = ChatTimelineHeightEstimator.estimate(text: withCode, columnWidth: width)
            - ChatTimelineHeightEstimator.estimate(text: prose, columnWidth: width)
        XCTAssertGreaterThan(delta, 30 * 15, "30 code lines should add roughly 30 line-heights")
    }

    func testCodeFenceContentNotPricedAsWrappedProse() {
        // A long unwrappable code line must be priced as ONE code line, not
        // as many wrapped prose lines.
        let longCodeLine = String(repeating: "x", count: 2_000)
        let fenced = "```\n" + longCodeLine + "\n```"
        let estimate = ChatTimelineHeightEstimator.estimate(text: fenced, columnWidth: width)
        XCTAssertLessThan(estimate, 250)
    }

    func testEstimateGrowsMonotonicallyWithContent() {
        let base = String(repeating: "汉字内容测试", count: 30)
        let bigger = base + base
        XCTAssertGreaterThan(
            ChatTimelineHeightEstimator.estimate(text: bigger, columnWidth: width),
            ChatTimelineHeightEstimator.estimate(text: base, columnWidth: width)
        )
    }

    func testNarrowerColumnEstimatesTaller() {
        let text = String(repeating: "这是一段比较长的中文内容，会随着列宽变窄而折出更多行。", count: 10)
        XCTAssertGreaterThan(
            ChatTimelineHeightEstimator.estimate(text: text, columnWidth: 400),
            ChatTimelineHeightEstimator.estimate(text: text, columnWidth: 900)
        )
    }

    func testMinimumHeightForTinyMessages() {
        // Short turns still need full chrome (header + bubble pad + footer
        // actions + row pad). Under-counting here was the send-path overlap
        // where the action strip painted into the streaming bubble.
        XCTAssertGreaterThanOrEqual(
            ChatTimelineHeightEstimator.estimate(text: "好", columnWidth: width),
            96
        )
    }

    func testShortUserTurnReservesFooterChrome() {
        let shortCJK = "foot和zsh区别"
        let estimate = ChatTimelineHeightEstimator.estimate(text: shortCJK, columnWidth: width)
        // Must clear bubble+header+footer (~110) so the first paint does not
        // clip the action cluster into the next row.
        XCTAssertGreaterThanOrEqual(estimate, 110)
    }
}
