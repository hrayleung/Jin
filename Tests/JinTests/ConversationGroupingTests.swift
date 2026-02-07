import XCTest
@testable import Jin

final class ConversationGroupingTests: XCTestCase {
    func testGroupedConversations_includesStarredSectionFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-07T12:00:00Z"))

        let modelConfigData = try JSONEncoder().encode(GenerationControls())

        let pinnedRecent = ConversationEntity(
            title: "Pinned Recent",
            isStarred: true,
            createdAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now)),
            updatedAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now)),
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        let pinnedOld = ConversationEntity(
            title: "Pinned Old",
            isStarred: true,
            createdAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: now)),
            updatedAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: now)),
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        let todayNewest = ConversationEntity(
            title: "Today Newest",
            createdAt: now,
            updatedAt: now,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        let todayOlder = ConversationEntity(
            title: "Today Older",
            createdAt: try XCTUnwrap(calendar.date(byAdding: .hour, value: -1, to: now)),
            updatedAt: try XCTUnwrap(calendar.date(byAdding: .hour, value: -1, to: now)),
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        let yesterday = ConversationEntity(
            title: "Yesterday",
            createdAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now)),
            updatedAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now)),
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        let previous7Days = ConversationEntity(
            title: "Previous 7 Days",
            createdAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: now)),
            updatedAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: now)),
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        let older = ConversationEntity(
            title: "Older",
            createdAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: now)),
            updatedAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: now)),
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        let grouped = ConversationGrouping.groupedConversations(
            [older, pinnedOld, previous7Days, todayOlder, pinnedRecent, yesterday, todayNewest],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(grouped.map(\.key), ["Starred", "Today", "Yesterday", "Previous 7 Days", "Older"])

        XCTAssertEqual(grouped[0].value.map(\.title), ["Pinned Recent", "Pinned Old"])
        XCTAssertEqual(grouped[1].value.map(\.title), ["Today Newest", "Today Older"])
    }

    func testGroupedConversations_omitsStarredSectionWhenEmpty() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-07T12:00:00Z"))
        let modelConfigData = try JSONEncoder().encode(GenerationControls())

        let today = ConversationEntity(
            title: "Today",
            createdAt: now,
            updatedAt: now,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        let grouped = ConversationGrouping.groupedConversations([today], now: now, calendar: calendar)
        XCTAssertEqual(grouped.map(\.key), ["Today"])
    }

    func testRelativeDateString_classifiesDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-07T12:00:00Z"))

        XCTAssertEqual(ConversationGrouping.relativeDateString(for: now, now: now, calendar: calendar), "Today")

        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        XCTAssertEqual(ConversationGrouping.relativeDateString(for: yesterday, now: now, calendar: calendar), "Yesterday")

        let previous7Days = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: now))
        XCTAssertEqual(ConversationGrouping.relativeDateString(for: previous7Days, now: now, calendar: calendar), "Previous 7 Days")

        let older = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: now))
        XCTAssertEqual(ConversationGrouping.relativeDateString(for: older, now: now, calendar: calendar), "Older")
    }
}

