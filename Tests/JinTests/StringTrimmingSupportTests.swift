import XCTest
@testable import Jin

final class StringTrimmingSupportTests: XCTestCase {
    func testTrimmedRemovesSurroundingWhitespaceAndNewlines() {
        XCTAssertEqual(" \n token\t ".trimmed, "token")
    }

    func testTrimmedLowercasedRemovesWhitespaceAndLowercases() {
        XCTAssertEqual(" \n ToKeN\t ".trimmedLowercased, "token")
    }

    func testTrimmedNonEmptyReturnsTrimmedValue() {
        XCTAssertEqual(" token ".trimmedNonEmpty, "token")
    }

    func testTrimmedNonEmptyReturnsNilForBlankStrings() {
        XCTAssertNil(" \n\t ".trimmedNonEmpty)
    }
}
