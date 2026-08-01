import XCTest
@testable import Jin

final class ChatTimelineScrollPrewarmPlannerTests: XCTestCase {

    // MARK: - Candidate rows

    func testCandidatesPrioritizeRowsAboveNearestFirst() {
        let candidates = ChatTimelineScrollPrewarmPlanner.candidateRows(
            rowCount: 40,
            visibleRange: 20..<23
        )
        // 8 above nearest-first, then 4 below starting at the range's end.
        XCTAssertEqual(candidates, [19, 18, 17, 16, 15, 14, 13, 12, 23, 24, 25, 26])
    }

    func testCandidatesClampAtTheTopOfTheConversation() {
        let candidates = ChatTimelineScrollPrewarmPlanner.candidateRows(
            rowCount: 40,
            visibleRange: 2..<5
        )
        XCTAssertEqual(candidates, [1, 0, 5, 6, 7, 8])
    }

    func testCandidatesClampAtTheBottomOfTheConversation() {
        let candidates = ChatTimelineScrollPrewarmPlanner.candidateRows(
            rowCount: 25,
            visibleRange: 20..<24
        )
        XCTAssertEqual(candidates, [19, 18, 17, 16, 15, 14, 13, 12, 24])
    }

    func testCandidatesExcludeTheVisibleRangeAndHandleEmptyTables() {
        XCTAssertEqual(
            ChatTimelineScrollPrewarmPlanner.candidateRows(rowCount: 0, visibleRange: 0..<0),
            []
        )
        let candidates = ChatTimelineScrollPrewarmPlanner.candidateRows(
            rowCount: 10,
            visibleRange: 0..<10
        )
        XCTAssertTrue(candidates.isEmpty, "a fully visible table has nothing to warm")
    }

    // MARK: - Item extraction

    func testExtractionSkipsUserMessages() {
        let item = ChatTimelineScrollPrewarmPlanner.prewarmItems(
            for: makeItem(role: .user, text: "A question"),
            renderMode: .fullWeb
        )
        XCTAssertTrue(item.isEmpty)
    }

    func testExtractionSkipsCollapsedPreviews() {
        let item = ChatTimelineScrollPrewarmPlanner.prewarmItems(
            for: makeItem(role: .assistant, text: "Long answer"),
            renderMode: .collapsedPreview
        )
        XCTAssertTrue(item.isEmpty)
    }

    func testExtractionMapsRenderModeToThePlainTextFlag() {
        let rich = ChatTimelineScrollPrewarmPlanner.prewarmItems(
            for: makeItem(role: .assistant, text: "**Rich** answer"),
            renderMode: .fullWeb
        )
        XCTAssertEqual(rich.map(\.renderPlainText), [false])
        XCTAssertEqual(rich.map(\.markdownText), ["**Rich** answer"])

        let plain = ChatTimelineScrollPrewarmPlanner.prewarmItems(
            for: makeItem(role: .assistant, text: "Plain answer"),
            renderMode: .nativeText
        )
        XCTAssertEqual(plain.map(\.renderPlainText), [true])
    }

    // MARK: - Fixtures

    private func makeItem(role: MessageRole, text: String) -> MessageRenderItem {
        let id = UUID()
        return MessageRenderItem(
            id: id,
            role: role.rawValue,
            timestamp: Date(),
            renderedBlocks: [.content(anchorID: "\(id)-0", part: .text(text))],
            toolCalls: [],
            searchActivities: [],
            codeExecutionActivities: [],
            assistantModelLabel: nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: text,
            preferredRenderMode: .fullWeb,
            isMemoryIntensiveAssistantContent: false,
            collapsedPreview: nil,
            canEditUserMessage: role == .user,
            canDeleteResponse: false,
            perMessageMCPServerNames: []
        )
    }
}
