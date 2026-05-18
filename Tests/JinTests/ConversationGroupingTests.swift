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

    func testGroupedConversations_usesLatestUserMessageDateInsteadOfMetadataUpdatedAt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-07T12:00:00Z"))
        let oldUserMessageDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: now))
        let modelConfigData = try JSONEncoder().encode(GenerationControls())

        let oldChatTouchedToday = ConversationEntity(
            title: "Old Chat Touched Today",
            createdAt: oldUserMessageDate,
            updatedAt: now,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )
        oldChatTouchedToday.messages.append(try message(role: .user, timestamp: oldUserMessageDate))

        let todayChat = ConversationEntity(
            title: "Today Chat",
            createdAt: now,
            updatedAt: now,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )
        todayChat.messages.append(try message(role: .user, timestamp: now))

        let grouped = ConversationGrouping.groupedConversations(
            [oldChatTouchedToday, todayChat],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(grouped.map(\.key), ["Today", "Older"])
        XCTAssertEqual(grouped[0].value.map(\.title), ["Today Chat"])
        XCTAssertEqual(grouped[1].value.map(\.title), ["Old Chat Touched Today"])
    }

    func testActivityDatePrefersLatestUserMessageOverNewerAssistantReply() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-07T12:00:00Z"))
        let userMessageDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: now))
        let assistantReplyDate = try XCTUnwrap(calendar.date(byAdding: .minute, value: -1, to: now))
        let modelConfigData = try JSONEncoder().encode(GenerationControls())

        let conversation = ConversationEntity(
            title: "Old User Turn",
            createdAt: userMessageDate,
            updatedAt: now,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )
        conversation.messages.append(try message(role: .user, timestamp: userMessageDate))
        conversation.messages.append(try message(role: .assistant, timestamp: assistantReplyDate))

        XCTAssertEqual(ConversationActivitySupport.activityDate(for: conversation), userMessageDate)
    }

    func testActivityDateFallsBackToLatestMessageWhenNoUserMessages() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-07T12:00:00Z"))
        let earlierAssistantDate = try XCTUnwrap(calendar.date(byAdding: .hour, value: -6, to: now))
        let latestAssistantDate = try XCTUnwrap(calendar.date(byAdding: .hour, value: -2, to: now))
        let modelConfigData = try JSONEncoder().encode(GenerationControls())

        let conversation = ConversationEntity(
            title: "Assistant Only",
            createdAt: try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: now)),
            updatedAt: now,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )
        conversation.messages.append(try message(role: .assistant, timestamp: earlierAssistantDate))
        conversation.messages.append(try message(role: .assistant, timestamp: latestAssistantDate))

        XCTAssertEqual(ConversationActivitySupport.activityDate(for: conversation), latestAssistantDate)
    }

    func testActivityDateFallsBackToCreatedAtWhenNoMessages() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-07T12:00:00Z"))
        let createdAt = now.addingTimeInterval(-86400 * 9)
        let modelConfigData = try JSONEncoder().encode(GenerationControls())

        let conversation = ConversationEntity(
            title: "No Messages",
            createdAt: createdAt,
            updatedAt: now,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: modelConfigData
        )

        XCTAssertEqual(ConversationActivitySupport.activityDate(for: conversation), createdAt)
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

    private func message(role: MessageRole, timestamp: Date) throws -> MessageEntity {
        let contentData = try JSONEncoder().encode([ContentPart.text("Test message")])
        return MessageEntity(
            role: role.rawValue,
            timestamp: timestamp,
            contentData: contentData
        )
    }
}
