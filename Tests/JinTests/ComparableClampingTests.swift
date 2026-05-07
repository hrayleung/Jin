import XCTest
@testable import Jin

final class ComparableClampingTests: XCTestCase {
    func testClampedReturnsValueInsideRange() {
        XCTAssertEqual(12.clamped(to: 1...50), 12)
    }

    func testClampedReturnsLowerBoundForValueBelowRange() {
        XCTAssertEqual((-2).clamped(to: 1...50), 1)
    }

    func testClampedReturnsUpperBoundForValueAboveRange() {
        XCTAssertEqual(99.clamped(to: 1...50), 50)
    }
}
