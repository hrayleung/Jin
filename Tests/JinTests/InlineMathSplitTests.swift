import XCTest
@testable import Jin

/// `InlineMath.split` detection guards: currency, tickers, and stray `$`
/// pairs must never be mis-detected as math spans (the prose between the
/// dollars would render as a garbage formula); real short formulas must
/// still split.
final class InlineMathSplitTests: XCTestCase {
    private func mathInners(_ s: String) -> [String] {
        InlineMath.split(s).compactMap {
            if case .math(let inner, _) = $0 { return inner }
            return nil
        }
    }

    private func reassembled(_ s: String) -> String {
        InlineMath.split(s).map {
            switch $0 {
            case .text(let t): return t
            case .math(_, let original): return original
            }
        }.joined()
    }

    // MARK: - Real math still splits

    func testSimpleDollarFormulaSplits() {
        XCTAssertEqual(mathInners("当 $x > 0$ 时递增"), ["x > 0"])
    }

    func testSubscriptNodesStillSplit() {
        XCTAssertEqual(
            mathInners("已知 $(x_0, y_0), (x_1, y_1)$ 两点"),
            ["(x_0, y_0), (x_1, y_1)"]
        )
    }

    func testParenDelimitedFormulaSplits() {
        XCTAssertEqual(mathInners("函数 \\(g(x) = e^x\\) 恒为正"), ["g(x) = e^x"])
    }

    func testSplitIsLossless() {
        let cases = [
            "当 $x > 0$ 时函数 $f(x) = x^2$ 单调递增",
            "预算在 $100–$200 之间；另外 $5 和 $10。",
            "关注 $AAPL、$TSLA 两只股票。",
            "转义 \\$50 和公式 $a+b$ 混排。",
        ]
        for input in cases {
            XCTAssertEqual(reassembled(input), input, "split must reassemble to the input")
        }
    }

    // MARK: - Currency / ticker guards

    func testCurrencyRangeIsNotMath() {
        XCTAssertTrue(mathInners("预算在 $100–$200 之间").isEmpty)
    }

    func testSpacedCurrencyAmountsAreNotMath() {
        XCTAssertTrue(mathInners("between $5 and $10 per unit").isEmpty)
    }

    func testEscapedDollarIsNotMath() {
        XCTAssertTrue(mathInners("价格是 \\$50 左右").isEmpty)
    }

    func testCJKTickerListIsNotMath() {
        // `$AAPL、$TSLA` — the close-candidate is preceded by CJK punctuation;
        // the span contains CJK so it must be rejected.
        XCTAssertTrue(mathInners("关注 $AAPL、$TSLA 两只股票").isEmpty)
    }

    func testCJKContentBetweenDollarsIsNotMath() {
        XCTAssertTrue(mathInners("成本 $一百元$ 左右").isEmpty)
    }

    func testEscapedCJKParenthesesAreNotMath() {
        // LLMs escape parens in CJK prose: `\(约 100 元\)` is not a formula.
        XCTAssertTrue(mathInners("成本\\(约 100 元\\)上下").isEmpty)
    }

    func testOverlongSpanIsNotMath() {
        let filler = String(repeating: "a+b ", count: 60) // 240 chars
        XCTAssertTrue(mathInners("$" + filler + "x$ end").isEmpty)
    }

    func testTrailingPriceAfterRealFormulaStillGuarded() {
        // One real formula plus a later stray `$` must not merge.
        let inners = mathInners("公式 $E=mc^2$ 与价格 $99 美元")
        XCTAssertEqual(inners, ["E=mc^2"])
    }
}
