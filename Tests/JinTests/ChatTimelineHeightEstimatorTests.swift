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
        XCTAssertGreaterThan(
            ChatTimelineHeightEstimator.estimate(text: cjk, columnWidth: width),
            ChatTimelineHeightEstimator.estimate(text: latin, columnWidth: width) * 1.5
        )
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
        XCTAssertGreaterThanOrEqual(
            ChatTimelineHeightEstimator.estimate(text: "好", columnWidth: width),
            44
        )
    }
}
