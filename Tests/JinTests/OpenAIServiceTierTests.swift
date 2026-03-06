import XCTest
@testable import Jin

final class OpenAIServiceTierTests: XCTestCase {
    func testNormalizedRecognizesKnownValues() {
        XCTAssertEqual(OpenAIServiceTier.normalized(rawValue: "priority"), .priority)
        XCTAssertEqual(OpenAIServiceTier.normalized(rawValue: " default "), .defaultTier)
        XCTAssertEqual(OpenAIServiceTier.normalized(rawValue: "FLEX"), .flex)
        XCTAssertEqual(OpenAIServiceTier.normalized(rawValue: "scale"), .scale)
    }

    func testNormalizedTreatsAutoAsUnset() {
        XCTAssertNil(OpenAIServiceTier.normalized(rawValue: nil))
        XCTAssertNil(OpenAIServiceTier.normalized(rawValue: ""))
        XCTAssertNil(OpenAIServiceTier.normalized(rawValue: "auto"))
        XCTAssertNil(OpenAIServiceTier.normalized(rawValue: "AUTO"))
    }
}
