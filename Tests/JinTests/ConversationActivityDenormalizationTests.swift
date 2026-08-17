import XCTest
@testable import Jin

/// The sidebar sorts and groups every conversation by activity date on every
/// body evaluation. Deriving that from the `messages` relationship issued one
/// SQL fetch per conversation and froze the main thread for hundreds of
/// milliseconds after any SwiftData save (captured in a hang stack:
/// `latestUserMessageDate` → `NSManagedObjectContext.executeFetchRequest`).
/// It is now denormalized onto `lastActivityAt`; these tests pin both the
/// semantics (unchanged) and the property that reads never touch `messages`.
final class ConversationActivityDenormalizationTests: XCTestCase {

    private let reference = Date(timeIntervalSince1970: 1_770_000_000)

    private func makeConversation(createdAt: Date) throws -> ConversationEntity {
        ConversationEntity(
            title: "Test",
            createdAt: createdAt,
            updatedAt: createdAt,
            providerID: "openai",
            modelID: "gpt-5.2",
            modelConfigData: try JSONEncoder().encode(GenerationControls())
        )
    }

    private func makeMessage(role: MessageRole, at timestamp: Date) throws -> MessageEntity {
        try MessageEntity.fromDomain(
            Message(role: role, content: [.text("hi")], timestamp: timestamp)
        )
    }

    /// A fresh conversation stores no activity date — seeding one would make a
    /// stale value authoritative for any entity whose `messages` are assigned
    /// without `refreshMessageCount()` (which is how the sidebar grouping tests
    /// build their fixtures). The read still answers `createdAt`.
    func testNewConversationHasNoStoredActivityDateAndReadsCreatedAt() throws {
        let conversation = try makeConversation(createdAt: reference)
        XCTAssertNil(conversation.lastActivityAt)
        XCTAssertEqual(ConversationActivitySupport.activityDate(for: conversation), reference)
    }

    /// Guards the regression that shipped briefly: with a seeded
    /// `lastActivityAt`, a conversation whose messages were attached directly
    /// reported its creation date instead of its newest message.
    func testDirectlyAttachedMessagesStillDriveTheDateBeforeAnyRefresh() throws {
        let conversation = try makeConversation(createdAt: reference)
        let assistantReply = reference.addingTimeInterval(3_600)
        conversation.messages = [try makeMessage(role: .assistant, at: assistantReply)]

        XCTAssertEqual(ConversationActivitySupport.activityDate(for: conversation), assistantReply)
    }

    func testRefreshPrefersTheLatestUserMessage() throws {
        let conversation = try makeConversation(createdAt: reference)
        let userTurn = reference.addingTimeInterval(60)
        let assistantReply = reference.addingTimeInterval(120)
        conversation.messages = [
            try makeMessage(role: .user, at: userTurn),
            try makeMessage(role: .assistant, at: assistantReply)
        ]

        conversation.refreshMessageCount()

        // Deliberately the *user* turn, not the later assistant reply: a long
        // reply must not reorder the sidebar past chats the user touched since.
        XCTAssertEqual(conversation.lastActivityAt, userTurn)
        XCTAssertEqual(conversation.messageCount, 2)
    }

    func testFallsBackToTheLatestMessageWhenThereIsNoUserTurn() throws {
        let conversation = try makeConversation(createdAt: reference)
        let assistantReply = reference.addingTimeInterval(300)
        conversation.messages = [try makeMessage(role: .assistant, at: assistantReply)]

        conversation.refreshMessageCount()

        XCTAssertEqual(conversation.lastActivityAt, assistantReply)
    }

    func testFallsBackToCreatedAtWhenEmptied() throws {
        let conversation = try makeConversation(createdAt: reference)
        conversation.messages = [try makeMessage(role: .user, at: reference.addingTimeInterval(60))]
        conversation.refreshMessageCount()

        conversation.messages = []
        conversation.refreshMessageCount()

        XCTAssertEqual(conversation.lastActivityAt, reference)
        XCTAssertEqual(conversation.messageCount, 0)
    }

    /// The point of the fix: the sidebar read is served entirely by the stored
    /// value, so a stale/unsynced relationship can never drag it back into a
    /// fetch. A sentinel that disagrees with `messages` proves it never looks.
    func testActivityDateReadsTheStoredValueAndIgnoresMessages() throws {
        let conversation = try makeConversation(createdAt: reference)
        conversation.messages = [
            try makeMessage(role: .user, at: reference.addingTimeInterval(9_999))
        ]
        let sentinel = reference.addingTimeInterval(-4_242)
        conversation.lastActivityAt = sentinel

        XCTAssertEqual(ConversationActivitySupport.activityDate(for: conversation), sentinel)
    }

    /// Rows written before the attribute existed still sort correctly until the
    /// post-launch backfill reaches them.
    func testActivityDateFallsBackForRowsNotYetBackfilled() throws {
        let conversation = try makeConversation(createdAt: reference)
        let userTurn = reference.addingTimeInterval(60)
        conversation.messages = [
            try makeMessage(role: .user, at: userTurn),
            try makeMessage(role: .assistant, at: reference.addingTimeInterval(120))
        ]
        conversation.lastActivityAt = nil

        XCTAssertEqual(ConversationActivitySupport.activityDate(for: conversation), userTurn)
    }

    func testSortingByActivityUsesTheStoredValue() throws {
        let older = try makeConversation(createdAt: reference)
        older.lastActivityAt = reference
        let newer = try makeConversation(createdAt: reference.addingTimeInterval(-10_000))
        newer.lastActivityAt = reference.addingTimeInterval(500)

        let sorted = ConversationActivitySupport.sortedByActivityDescending([older, newer])

        XCTAssertEqual(sorted.map(\.lastActivityAt), [newer.lastActivityAt, older.lastActivityAt])
    }
}
