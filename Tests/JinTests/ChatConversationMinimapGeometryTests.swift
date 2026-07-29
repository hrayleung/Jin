import XCTest
@testable import Jin

/// Covers the pure layer behind the conversation minimap: how messages group
/// into navigable turns, how excerpts are shaped for the hover card, how the
/// tick window slides in long conversations, and how far the render window has
/// to open to reach an old turn.
final class ChatConversationMinimapGeometryTests: XCTestCase {

    // MARK: - Turn grouping

    func testPairsEachUserMessageWithItsReply() {
        let list = ChatConversationMinimapGeometry.turnList(from: [
            makeItem(.user, "first question"),
            makeItem(.assistant, "first answer"),
            makeItem(.user, "second question"),
            makeItem(.assistant, "second answer"),
        ])

        XCTAssertEqual(list.turns.count, 2)
        XCTAssertEqual(list.turns[0].userExcerpt, "first question")
        XCTAssertEqual(list.turns[0].assistantExcerpt, "first answer")
        XCTAssertEqual(list.turns[1].userExcerpt, "second question")
        XCTAssertEqual(list.turns[1].assistantExcerpt, "second answer")
        XCTAssertEqual(list.turns.map(\.index), [0, 1])
    }

    func testTurnAnchorsOnTheUserMessage() {
        let question = makeItem(.user, "q")
        let answer = makeItem(.assistant, "a")
        let list = ChatConversationMinimapGeometry.turnList(from: [question, answer])

        XCTAssertEqual(list.turns.first?.id, question.id, "a jump should land on the question")
    }

    func testBackToBackUserMessagesEachOpenATurn() {
        let list = ChatConversationMinimapGeometry.turnList(from: [
            makeItem(.user, "one"),
            makeItem(.user, "two"),
            makeItem(.assistant, "answer to two"),
        ])

        XCTAssertEqual(list.turns.count, 2)
        XCTAssertEqual(list.turns[0].assistantExcerpt, "", "the abandoned turn has no reply")
        XCTAssertEqual(list.turns[1].assistantExcerpt, "answer to two")
    }

    func testLeadingAssistantMessageStillGetsATurn() {
        let greeting = makeItem(.assistant, "hello there")
        let list = ChatConversationMinimapGeometry.turnList(from: [
            greeting,
            makeItem(.user, "hi"),
            makeItem(.assistant, "how can I help"),
        ])

        XCTAssertEqual(list.turns.count, 2)
        XCTAssertEqual(list.turns[0].id, greeting.id)
        XCTAssertEqual(list.turns[0].userExcerpt, "")
        XCTAssertEqual(list.turns[0].assistantExcerpt, "hello there")
    }

    func testToolMessagesDoNotOpenTurnsButStayMappedToTheirTurn() {
        let question = makeItem(.user, "run the tool")
        let toolResult = makeItem(.tool, "tool output")
        let answer = makeItem(.assistant, "done")
        let list = ChatConversationMinimapGeometry.turnList(from: [question, toolResult, answer])

        XCTAssertEqual(list.turns.count, 1)
        XCTAssertEqual(list.turns[0].assistantExcerpt, "done")
        // Scrolling past the tool row must not blank out the active tick.
        XCTAssertEqual(list.turnIndex(forMessageID: toolResult.id), 0)
    }

    func testEveryMessageMapsBackToItsTurn() {
        let q1 = makeItem(.user, "q1")
        let a1 = makeItem(.assistant, "a1")
        let q2 = makeItem(.user, "q2")
        let a2 = makeItem(.assistant, "a2")
        let list = ChatConversationMinimapGeometry.turnList(from: [q1, a1, q2, a2])

        XCTAssertEqual(list.turnIndex(forMessageID: q1.id), 0)
        XCTAssertEqual(list.turnIndex(forMessageID: a1.id), 0)
        XCTAssertEqual(list.turnIndex(forMessageID: q2.id), 1)
        XCTAssertEqual(list.turnIndex(forMessageID: a2.id), 1)
        XCTAssertNil(list.turnIndex(forMessageID: UUID()))
        XCTAssertNil(list.turnIndex(forMessageID: nil))
    }

    func testFirstReplyWinsWhenAnAssistantSpeaksTwice() {
        let list = ChatConversationMinimapGeometry.turnList(from: [
            makeItem(.user, "q"),
            makeItem(.assistant, "first part"),
            makeItem(.assistant, "continuation"),
        ])

        XCTAssertEqual(list.turns.count, 1)
        XCTAssertEqual(list.turns[0].assistantExcerpt, "first part")
    }

    func testEmptyConversationProducesNoTurns() {
        XCTAssertEqual(ChatConversationMinimapGeometry.turnList(from: []).turns.count, 0)
    }

    // MARK: - Excerpts

    func testExcerptCollapsesWhitespaceRunsToSingleSpaces() {
        XCTAssertEqual(
            ChatConversationMinimapGeometry.excerpt("  hello\n\n   world \t!  ", limit: 100),
            "hello world !"
        )
    }

    func testExcerptEllipsizesOnlyWhenContentIsActuallyCut() {
        XCTAssertEqual(ChatConversationMinimapGeometry.excerpt("abcdef", limit: 6), "abcdef")
        XCTAssertEqual(ChatConversationMinimapGeometry.excerpt("abcdefg", limit: 6), "abcdef…")
    }

    func testExcerptDoesNotEllipsizeOnTrailingWhitespaceAlone() {
        XCTAssertEqual(
            ChatConversationMinimapGeometry.excerpt("abcdef   \n\n ", limit: 6),
            "abcdef",
            "trailing blanks are not content"
        )
    }

    func testExcerptHandlesDegenerateInput() {
        XCTAssertEqual(ChatConversationMinimapGeometry.excerpt("", limit: 10), "")
        XCTAssertEqual(ChatConversationMinimapGeometry.excerpt("   \n  ", limit: 10), "")
        XCTAssertEqual(ChatConversationMinimapGeometry.excerpt("anything", limit: 0), "")
    }

    func testExcerptKeepsCJKIntact() {
        XCTAssertEqual(
            ChatConversationMinimapGeometry.excerpt("怎么连接 docker registry", limit: 100),
            "怎么连接 docker registry"
        )
    }

    // MARK: - Tick layout

    func testAllTurnsShownWhenTheyFit() {
        let layout = ChatConversationMinimapGeometry.layout(
            turnCount: 8,
            activeIndex: 3,
            availableHeight: 400,
            pitch: 10
        )

        XCTAssertEqual(layout.visibleRange, 0..<8)
        XCTAssertFalse(layout.fadesTop)
        XCTAssertFalse(layout.fadesBottom)
    }

    func testWindowCentresOnTheActiveTurnWhenOverflowing() {
        // 200pt / 10pt pitch = 20 ticks of capacity, 100 turns.
        let layout = ChatConversationMinimapGeometry.layout(
            turnCount: 100,
            activeIndex: 50,
            availableHeight: 200,
            pitch: 10
        )

        XCTAssertEqual(layout.visibleRange.count, 20)
        XCTAssertTrue(layout.visibleRange.contains(50))
        XCTAssertEqual(layout.visibleRange, 40..<60)
        XCTAssertTrue(layout.fadesTop)
        XCTAssertTrue(layout.fadesBottom)
    }

    func testWindowClampsAtTheStart() {
        let layout = ChatConversationMinimapGeometry.layout(
            turnCount: 100,
            activeIndex: 1,
            availableHeight: 200,
            pitch: 10
        )

        XCTAssertEqual(layout.visibleRange, 0..<20)
        XCTAssertFalse(layout.fadesTop)
        XCTAssertTrue(layout.fadesBottom)
    }

    func testWindowClampsAtTheEnd() {
        let layout = ChatConversationMinimapGeometry.layout(
            turnCount: 100,
            activeIndex: 99,
            availableHeight: 200,
            pitch: 10
        )

        XCTAssertEqual(layout.visibleRange, 80..<100)
        XCTAssertTrue(layout.fadesTop)
        XCTAssertFalse(layout.fadesBottom)
    }

    func testNoReportedPositionAnchorsOnTheNewestTurn() {
        let layout = ChatConversationMinimapGeometry.layout(
            turnCount: 100,
            activeIndex: nil,
            availableHeight: 200,
            pitch: 10
        )

        XCTAssertTrue(layout.visibleRange.contains(99), "a freshly opened chat sits at the bottom")
        XCTAssertFalse(layout.fadesBottom)
    }

    func testLayoutSurvivesDegenerateGeometry() {
        let empty = ChatConversationMinimapGeometry.layout(
            turnCount: 0,
            activeIndex: nil,
            availableHeight: 400,
            pitch: 10
        )
        XCTAssertEqual(empty.visibleRange, 0..<0)

        // Zero height must still yield one legal tick rather than an empty or
        // negative range.
        let squeezed = ChatConversationMinimapGeometry.layout(
            turnCount: 5,
            activeIndex: 2,
            availableHeight: 0,
            pitch: 10
        )
        XCTAssertEqual(squeezed.visibleRange.count, 1)
        XCTAssertTrue(squeezed.visibleRange.contains(2))

        let zeroPitch = ChatConversationMinimapGeometry.layout(
            turnCount: 5,
            activeIndex: 0,
            availableHeight: 100,
            pitch: 0
        )
        XCTAssertEqual(zeroPitch.visibleRange, 0..<5)
    }

    func testOutOfRangeActiveIndexIsClamped() {
        let layout = ChatConversationMinimapGeometry.layout(
            turnCount: 50,
            activeIndex: 999,
            availableHeight: 100,
            pitch: 10
        )
        XCTAssertEqual(layout.visibleRange, 40..<50)
    }

    // MARK: - Render window

    func testRenderLimitLeftAloneWhenTargetIsAlreadyLoaded() {
        // 100 messages, window of 24 → indices 76...99 are loaded.
        XCTAssertEqual(
            ChatConversationMinimapGeometry.renderLimit(toInclude: 90, totalCount: 100, currentLimit: 24),
            24
        )
    }

    func testRenderLimitOpensJustFarEnough() {
        XCTAssertEqual(
            ChatConversationMinimapGeometry.renderLimit(toInclude: 60, totalCount: 100, currentLimit: 24),
            40,
            "index 60 is the 40th message from the end"
        )
    }

    func testRenderLimitForTheOldestMessageCoversEverything() {
        XCTAssertEqual(
            ChatConversationMinimapGeometry.renderLimit(toInclude: 0, totalCount: 100, currentLimit: 24),
            100
        )
    }

    func testRenderLimitNeverShrinksTheWindow() {
        XCTAssertEqual(
            ChatConversationMinimapGeometry.renderLimit(toInclude: 99, totalCount: 100, currentLimit: 64),
            64
        )
    }

    func testRenderLimitClampsBadInput() {
        XCTAssertEqual(
            ChatConversationMinimapGeometry.renderLimit(toInclude: -5, totalCount: 10, currentLimit: 4),
            10
        )
        XCTAssertEqual(
            ChatConversationMinimapGeometry.renderLimit(toInclude: 999, totalCount: 10, currentLimit: 4),
            4
        )
        XCTAssertEqual(
            ChatConversationMinimapGeometry.renderLimit(toInclude: 0, totalCount: 0, currentLimit: 24),
            24
        )
    }

    // MARK: - Fixtures

    private func makeItem(_ role: MessageRole, _ copyText: String) -> MessageRenderItem {
        MessageRenderItem(
            id: UUID(),
            role: role.rawValue,
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: [],
            toolCalls: [],
            searchActivities: [],
            codeExecutionActivities: [],
            assistantModelLabel: nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: copyText,
            preferredRenderMode: .nativeText,
            isMemoryIntensiveAssistantContent: false,
            collapsedPreview: nil,
            canEditUserMessage: false,
            canDeleteResponse: false,
            perMessageMCPServerNames: []
        )
    }
}
