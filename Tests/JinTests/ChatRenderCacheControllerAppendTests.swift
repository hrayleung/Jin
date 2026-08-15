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

    func testAsyncRebuildFromEmptyPaintsTheProvisionalTailImmediately() async throws {
        let controller = ChatRenderCacheController()
        let t0 = Date(timeIntervalSince1970: 1_000)
        // A big head message trips the async heuristics; 30 messages total so
        // the provisional tail (24) is distinguishable from the full decode.
        var messages = [try makeMessageEntity(
            role: .user,
            text: String(repeating: "Long prompt line with embedded context.\n", count: 900)
        )]
        for index in 0..<29 {
            messages.append(try makeMessageEntity(
                role: index.isMultiple(of: 2) ? .assistant : .user,
                text: "message \(index)"
            ))
        }

        controller.rebuild(
            request: makeRequest(messages: messages, updatedAt: t0),
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )

        // Synchronously after rebuild() returns: the tail is already painted.
        XCTAssertEqual(controller.visibleMessages.count, ChatRenderProvisionalTailPolicy.maxMessages)
        XCTAssertEqual(controller.visibleMessages.last?.id, messages.last?.id)

        // The full decode then applies over the provisional state.
        let deadline = Date().addingTimeInterval(5)
        while controller.visibleMessages.count != messages.count {
            guard Date() < deadline else {
                return XCTFail("full decode never applied over the provisional tail")
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(controller.cachedTotalMessageCount, messages.count)
    }

    func testExactEditReplacesUserTurnAndDropsTheTail() throws {
        let controller = ChatRenderCacheController()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_001)
        let seeded = try [
            makeMessageEntity(role: .user, text: "Original question"),
            makeMessageEntity(role: .assistant, text: "Original answer"),
        ]
        rebuildSynchronously(controller, messages: seeded, updatedAt: t0)
        let versionAfterRebuild = controller.version
        let user = seeded[0]
        let updated = try ChatMessageEditingSupport.updateUserMessageContent(
            user,
            newText: "Edited question",
            existingContent: [.text("Original question")]
        )
        let history = ChatMessageEditingSupport.makeUpdatedUserMessage(
            from: nil,
            id: user.id,
            newContent: updated,
            timestamp: t1,
            perMessageMCPServerNames: nil
        )
        let renderItem = ChatMessageRenderPipeline.makeUserTurnRenderItem(
            from: history,
            artifactsEnabled: false
        )

        let applied = controller.applyEditedUserTurn(
            entity: user,
            historyMessage: history,
            renderItem: renderItem,
            keepMessageIDs: [user.id],
            previousUpdatedAt: t0,
            newUpdatedAt: t1,
            previousTotalMessageCount: 2,
            newTotalMessageCount: 1
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(controller.visibleMessages.count, 1)
        XCTAssertEqual(controller.visibleMessages.first?.id, user.id)
        XCTAssertEqual(controller.visibleMessages.first?.copyText, "Edited question")
        XCTAssertEqual(controller.activeThreadHistory.count, 1)
        guard case .text(let historyText) = controller.activeThreadHistory.first?.content.first else {
            return XCTFail("Expected the edited history message to keep a text part")
        }
        XCTAssertEqual(historyText, "Edited question")
        XCTAssertEqual(controller.cachedTotalMessageCount, 1)
        XCTAssertEqual(controller.version, versionAfterRebuild &+ 1)
        XCTAssertNil(controller.messageEntitiesByID[seeded[1].id])

        let versionAfterEdit = controller.version
        controller.rebuildIfNeeded(
            request: makeRequest(messages: [user], updatedAt: t1),
            assistantProviderIconID: { _ in nil },
            isStillCurrent: { _, _ in true },
            onContextApplied: {},
            onHistoryReady: {}
        )
        XCTAssertEqual(controller.version, versionAfterEdit, "exact edit must suppress the follow-up rebuild")
    }

    func testStaleEditStillPaintsTheNewText() throws {
        let controller = ChatRenderCacheController()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let seeded = try [
            makeMessageEntity(role: .user, text: "Original"),
            makeMessageEntity(role: .assistant, text: "Answer"),
        ]
        rebuildSynchronously(controller, messages: seeded, updatedAt: t0)
        let user = seeded[0]
        let history = Message(id: user.id, role: .user, content: [.text("Edited")], timestamp: t0)
        let renderItem = ChatMessageRenderPipeline.makeUserTurnRenderItem(
            from: history,
            artifactsEnabled: false
        )

        let applied = controller.applyEditedUserTurn(
            entity: user,
            historyMessage: history,
            renderItem: renderItem,
            keepMessageIDs: [user.id],
            previousUpdatedAt: Date(timeIntervalSince1970: 999),
            newUpdatedAt: Date(timeIntervalSince1970: 1_001),
            previousTotalMessageCount: 2,
            newTotalMessageCount: 1
        )

        XCTAssertFalse(applied)
        XCTAssertEqual(controller.visibleMessages.first?.copyText, "Edited")
        XCTAssertEqual(controller.visibleMessages.count, 1)
    }

    func testEditCancelsPendingDebounceSoExactPathCanAdvance() throws {
        let controller = ChatRenderCacheController()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_001)
        let seeded = try [makeMessageEntity(role: .user, text: "Original")]
        rebuildSynchronously(controller, messages: seeded, updatedAt: t0)
        controller.scheduleDebouncedRebuild(after: .seconds(30)) {}

        let user = seeded[0]
        let history = Message(id: user.id, role: .user, content: [.text("Edited")], timestamp: t1)
        let renderItem = ChatMessageRenderPipeline.makeUserTurnRenderItem(
            from: history,
            artifactsEnabled: false
        )
        let applied = controller.applyEditedUserTurn(
            entity: user,
            historyMessage: history,
            renderItem: renderItem,
            keepMessageIDs: [user.id],
            previousUpdatedAt: t0,
            newUpdatedAt: t1,
            previousTotalMessageCount: 1,
            newTotalMessageCount: 1
        )

        XCTAssertTrue(applied, "a leftover debounce must not force a full rebuild after an in-place edit")
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
