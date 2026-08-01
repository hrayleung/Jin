import XCTest
@testable import Jin

/// `appendUserTurn` is the send-path fast append: the row must always paint
/// (unconditional append) while the bookkeeping advances ONLY when the
/// controller was provably in sync — otherwise the caller runs a full rebuild
/// and the failure mode is exactly today's behavior.
@MainActor
final class ChatRenderCacheControllerAppendTests: XCTestCase {

    func testExactAppendAdvancesBookkeepingAndSuppressesRebuild() throws {
        let controller = ChatRenderCacheController()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_001)
        let seeded = try [
            makeMessageEntity(role: .user, text: "First question"),
            makeMessageEntity(role: .assistant, text: "First answer"),
        ]
        rebuildSynchronously(controller, messages: seeded, updatedAt: t0)
        XCTAssertEqual(controller.visibleMessages.count, 2)
        let versionAfterRebuild = controller.version

        let (entity, message, item) = try makeUserTurn(text: "Second question")
        let applied = controller.appendUserTurn(
            entity: entity,
            historyMessage: message,
            renderItem: item,
            previousUpdatedAt: t0,
            newUpdatedAt: t1,
            totalMessageCount: 3
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(controller.visibleMessages.count, 3)
        XCTAssertEqual(controller.visibleMessages.last?.id, entity.id)
        XCTAssertEqual(controller.activeThreadHistory.count, 3)
        XCTAssertEqual(controller.cachedTotalMessageCount, 3)
        XCTAssertEqual(controller.version, versionAfterRebuild &+ 1)
        XCTAssertNotNil(controller.messageEntitiesByID[entity.id])

        // The observer-driven rebuildIfNeeded must now be a no-op: the append
        // IS the rebuild's result for a tail user message.
        let versionAfterAppend = controller.version
        controller.rebuildIfNeeded(
            request: makeRequest(messages: seeded + [entity], updatedAt: t1),
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )
        XCTAssertEqual(controller.version, versionAfterAppend, "exact append must suppress the follow-up rebuild")
    }

    func testLaterRealChangeStillRebuilds() throws {
        let controller = ChatRenderCacheController()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_001)
        let t2 = Date(timeIntervalSince1970: 1_002)
        let seeded = try [
            makeMessageEntity(role: .user, text: "First question"),
            makeMessageEntity(role: .assistant, text: "First answer"),
        ]
        rebuildSynchronously(controller, messages: seeded, updatedAt: t0)

        let (entity, message, item) = try makeUserTurn(text: "Second question")
        XCTAssertTrue(controller.appendUserTurn(
            entity: entity,
            historyMessage: message,
            renderItem: item,
            previousUpdatedAt: t0,
            newUpdatedAt: t1,
            totalMessageCount: 3
        ))

        // The assistant reply lands: count and updatedAt both move, so the
        // suppression must not swallow this rebuild.
        let reply = try makeMessageEntity(role: .assistant, text: "Second answer")
        rebuildSynchronously(controller, messages: seeded + [entity, reply], updatedAt: t2, ifNeeded: true)
        XCTAssertEqual(controller.visibleMessages.count, 4)
    }

    func testStaleUpdatedAtAppendsButRequestsFullRebuild() throws {
        let controller = ChatRenderCacheController()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let seeded = try [makeMessageEntity(role: .user, text: "Hi")]
        rebuildSynchronously(controller, messages: seeded, updatedAt: t0)

        let (entity, message, item) = try makeUserTurn(text: "Follow-up")
        let applied = controller.appendUserTurn(
            entity: entity,
            historyMessage: message,
            renderItem: item,
            // A pending edit moved updatedAt since the last rebuild.
            previousUpdatedAt: Date(timeIntervalSince1970: 999),
            newUpdatedAt: Date(timeIntervalSince1970: 1_001),
            totalMessageCount: 2
        )

        XCTAssertFalse(applied)
        XCTAssertEqual(controller.visibleMessages.last?.id, entity.id, "the row must paint even when a rebuild follows")
    }

    func testAppendOntoFreshControllerRequestsFullRebuild() throws {
        let controller = ChatRenderCacheController()
        let (entity, message, item) = try makeUserTurn(text: "First send after switch")

        let applied = controller.appendUserTurn(
            entity: entity,
            historyMessage: message,
            renderItem: item,
            previousUpdatedAt: Date(timeIntervalSince1970: 1_000),
            newUpdatedAt: Date(timeIntervalSince1970: 1_001),
            totalMessageCount: 1
        )

        XCTAssertFalse(applied, "distantPast bookkeeping can never match — the full rebuild must run")
        XCTAssertEqual(controller.visibleMessages.count, 1)
    }

    func testAppendWhileBuildInFlightAppendsButRequestsFullRebuild() throws {
        let controller = ChatRenderCacheController()
        let t0 = Date(timeIntervalSince1970: 1_000)
        // A >=12KB single message forces the async decode path, whose build
        // task is assigned synchronously inside rebuild().
        let big = try makeMessageEntity(
            role: .user,
            text: String(repeating: "Long prompt line with embedded context.\n", count: 900)
        )
        controller.rebuild(
            request: makeRequest(messages: [big], updatedAt: t0),
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )

        let (entity, message, item) = try makeUserTurn(text: "Sent before the decode landed")
        let applied = controller.appendUserTurn(
            entity: entity,
            historyMessage: message,
            renderItem: item,
            previousUpdatedAt: t0,
            newUpdatedAt: Date(timeIntervalSince1970: 1_001),
            totalMessageCount: 2
        )

        XCTAssertFalse(applied, "an in-flight decode means the cache state is not provably current")
        XCTAssertEqual(controller.visibleMessages.last?.id, entity.id)
        controller.cancelPendingWork()
    }

    // MARK: - Fixtures

    private func rebuildSynchronously(
        _ controller: ChatRenderCacheController,
        messages: [MessageEntity],
        updatedAt: Date,
        ifNeeded: Bool = false
    ) {
        let request = makeRequest(messages: messages, updatedAt: updatedAt)
        if ifNeeded {
            controller.rebuildIfNeeded(
                request: request,
                assistantProviderIconID: { _ in nil },
                isStillCurrent: { _, _ in true },
                onContextApplied: {},
                onHistoryReady: {}
            )
        } else {
            controller.rebuild(
                request: request,
                assistantProviderIconID: { _ in nil },
                isStillCurrent: { _, _ in true },
                onContextApplied: {},
                onHistoryReady: {}
            )
        }
    }

    private func makeRequest(messages: [MessageEntity], updatedAt: Date) -> ChatRenderCacheRebuildRequest {
        ChatRenderCacheRebuildRequest(
            conversationID: Self.conversationID,
            allMessages: messages,
            orderedMessages: messages,
            updatedAt: updatedAt,
            fallbackModelLabel: "Model",
            artifactsEnabled: false,
            providerIconsByID: [:]
        )
    }

    private static let conversationID = UUID()

    private func makeUserTurn(text: String) throws -> (MessageEntity, Message, MessageRenderItem) {
        let entity = try makeMessageEntity(role: .user, text: text)
        let decoded = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: [PersistedMessageSnapshot(entity)],
            fallbackModelLabel: "Model",
            artifactsEnabled: false,
            assistantProviderIconsByID: [:]
        )
        let item = try XCTUnwrap(decoded.visibleMessages.first)
        let message = try XCTUnwrap(PersistedMessageSnapshot(entity).toDomain(using: JSONDecoder()))
        return (entity, message, item)
    }

    private func makeMessageEntity(role: MessageRole, text: String) throws -> MessageEntity {
        try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: role,
                content: [.text(text)],
                timestamp: Date()
            )
        )
    }
}
