import XCTest
@testable import Jin

final class UpdateSettingsFormattingTests: XCTestCase {
    func testRelativeTimestampUsesRelativeStyleWithinOneWeek() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fiveMinutesAgo = now.addingTimeInterval(-5 * 60)

        let text = UpdateSettingsFormatting.relativeTimestamp(fiveMinutesAgo, now: now)

        XCTAssertFalse(text.isEmpty)
        // RelativeDateTimeFormatter wording varies by locale; ensure it is not the absolute medium date format.
        XCTAssertFalse(text.contains(","))
    }

    func testRelativeTimestampFallsBackToAbsoluteStyleAfterOneWeek() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 24 * 60 * 60)

        let text = UpdateSettingsFormatting.relativeTimestamp(twoWeeksAgo, now: now)

        XCTAssertFalse(text.isEmpty)
        // Absolute formatter uses medium date + short time — expect at least a year token from the fixed epoch.
        XCTAssertTrue(text.contains("2023") || text.contains("23"))
    }
}
