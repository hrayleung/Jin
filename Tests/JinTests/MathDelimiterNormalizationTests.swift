import XCTest
@testable import Jin

final class MathDelimiterNormalizationTests: XCTestCase {
    func testNormalizingInlineMathDelimitersConvertsCommonFullwidthSymbols() {
        let raw = "其中 ＄＼mathcal{S}_V＄"
        XCTAssertEqual(raw.normalizingInlineMathDelimiters(), "其中 $\\mathcal{S}_V$")
    }
}

