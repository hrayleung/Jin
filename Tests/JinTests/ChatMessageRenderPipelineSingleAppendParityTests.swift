import XCTest
@testable import Jin

/// The send fast path builds the appended user turn's render item by running
/// the EXISTING pipeline over a one-element snapshot array. These pin the
/// claim that makes it safe: for a tail user message the single-message run
/// is indistinguishable from the full-conversation run, and appending one
/// cannot change any earlier item.
final class ChatMessageRenderPipelineSingleAppendParityTests: XCTestCase {

    func testSingleMessageRunMatchesFullRunForTheTailUserMessage() throws {
        let conversation = try makeConversation()
        let tail = try makeUserEntity(
            text: "Follow-up **with markdown** and `code`.",
            perMessageMCPServerNames: ["search", "files"]
        )
        let all = (conversation + [tail]).map(PersistedMessageSnapshot.init)

        let fullRun = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: all,
            fallbackModelLabel: "Model",
            artifactsEnabled: true,
            assistantProviderIconsByID: [:]
        )
        let singleRun = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: [PersistedMessageSnapshot(tail)],
            fallbackModelLabel: "Model",
            artifactsEnabled: true,
            assistantProviderIconsByID: [:]
        )

        let fromFull = try XCTUnwrap(fullRun.visibleMessages.last)
        let fromSingle = try XCTUnwrap(singleRun.visibleMessages.first)
        assertItemsEqual(fromSingle, fromFull)
    }

    func testAppendingATailUserMessageLeavesEarlierItemsUntouched() throws {
        let conversation = try makeConversation()
        let tail = try makeUserEntity(text: "Another question")

        let before = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: conversation.map(PersistedMessageSnapshot.init),
            fallbackModelLabel: "Model",
            artifactsEnabled: true,
            assistantProviderIconsByID: [:]
        )
        let after = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: (conversation + [tail]).map(PersistedMessageSnapshot.init),
            fallbackModelLabel: "Model",
            artifactsEnabled: true,
            assistantProviderIconsByID: [:]
        )

        XCTAssertEqual(after.visibleMessages.count, before.visibleMessages.count + 1)
        for (index, beforeItem) in before.visibleMessages.enumerated() {
            assertItemsEqual(after.visibleMessages[index], beforeItem)
        }
    }

    func testUserMessageNeverProducesArtifacts() throws {
        // Artifact markup in USER text must not mint catalog entries — only
        // assistant messages split artifacts. The fast path relies on this to
        // leave the catalog untouched.
        let user = try makeUserEntity(
            text: "<artifact identifier=\"demo\" type=\"text/html\" title=\"Demo\">\n<p>hi</p>\n</artifact>"
        )
        let context = ChatMessageRenderPipeline.makeDecodedRenderContext(
            from: [PersistedMessageSnapshot(user)],
            fallbackModelLabel: "Model",
            artifactsEnabled: true,
            assistantProviderIconsByID: [:]
        )
        XCTAssertTrue(context.artifactCatalog.isEmpty)
        XCTAssertTrue(context.toolResultsByCallID.isEmpty)
    }

    // MARK: - Fixtures

    private func assertItemsEqual(
        _ lhs: MessageRenderItem,
        _ rhs: MessageRenderItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.id, rhs.id, file: file, line: line)
        XCTAssertEqual(lhs.role, rhs.role, file: file, line: line)
        XCTAssertEqual(lhs.timestamp, rhs.timestamp, file: file, line: line)
        XCTAssertEqual(lhs.copyText, rhs.copyText, file: file, line: line)
        XCTAssertEqual(lhs.preferredRenderMode, rhs.preferredRenderMode, file: file, line: line)
        XCTAssertEqual(lhs.canEditUserMessage, rhs.canEditUserMessage, file: file, line: line)
        XCTAssertEqual(lhs.canDeleteResponse, rhs.canDeleteResponse, file: file, line: line)
        XCTAssertEqual(lhs.perMessageMCPServerNames, rhs.perMessageMCPServerNames, file: file, line: line)
        XCTAssertEqual(lhs.renderedBlocks.count, rhs.renderedBlocks.count, file: file, line: line)
        XCTAssertEqual(lhs.toolCalls.count, rhs.toolCalls.count, file: file, line: line)
        XCTAssertEqual(lhs.highlights, rhs.highlights, file: file, line: line)
    }

    /// A user/assistant exchange whose tail is a user message with a real
    /// follow-up structure (so canDeleteResponse has assistant runs to look at).
    private func makeConversation() throws -> [MessageEntity] {
        try [
            makeUserEntity(text: "First question"),
            makeEntity(role: .assistant, text: "First answer with a fair amount of text."),
            makeUserEntity(text: "Second question"),
            makeEntity(role: .assistant, text: "Second answer."),
        ]
    }

    private func makeUserEntity(
        text: String,
        perMessageMCPServerNames: [String]? = nil
    ) throws -> MessageEntity {
        try MessageEntity.fromDomain(
            Message(
                id: UUID(),
                role: .user,
                content: [.text(text)],
                timestamp: Date(),
                perMessageMCPServerNames: perMessageMCPServerNames
            )
        )
    }

    private func makeEntity(role: MessageRole, text: String) throws -> MessageEntity {
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
