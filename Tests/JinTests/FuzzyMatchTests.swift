import XCTest
@testable import Jin

final class FuzzyMatchTests: XCTestCase {
    func testSeparatorQueryMatchesTargetsContainingThatSeparator() {
        let result = FuzzyMatch.match(query: "-", target: "gpt-4o")

        XCTAssertTrue(result.matched)
    }

    func testSeparatorQueryDoesNotMatchTargetsWithoutThatSeparator() {
        let result = FuzzyMatch.match(query: "-", target: "gpt4o")

        XCTAssertFalse(result.matched)
    }

    func testRepeatedSeparatorQueryDoesNotMatchCollapsedTarget() {
        let result = FuzzyMatch.match(query: "---", target: "gpt-4o")

        XCTAssertFalse(result.matched)
    }
}
