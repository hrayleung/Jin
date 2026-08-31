import XCTest
@testable import Jin

final class ChatsSidebarSelectionSupportTests: XCTestCase {

    private let openID = UUID()
    private let otherID = UUID()

    // MARK: - openAction

    func testOpenAction_singleNewRowOpensIt() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.openAction(
                newSelection: [otherID],
                openConversationID: openID,
                openConversationIsListed: true
            ),
            .open(otherID)
        )
    }

    func testOpenAction_reselectingTheOpenChatKeepsIt() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.openAction(
                newSelection: [openID],
                openConversationID: openID,
                openConversationIsListed: true
            ),
            .keep
        )
    }

    func testOpenAction_multiSelectionNeverSwapsTheOpenChat() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.openAction(
                newSelection: [openID, otherID],
                openConversationID: openID,
                openConversationIsListed: true
            ),
            .keep
        )

        // Even when the open chat isn't part of the batch.
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.openAction(
                newSelection: [otherID, UUID()],
                openConversationID: openID,
                openConversationIsListed: true
            ),
            .keep
        )
    }

    func testOpenAction_emptySelectionClearsAListedChat() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.openAction(
                newSelection: [],
                openConversationID: openID,
                openConversationIsListed: true
            ),
            .clear
        )
    }

    /// A brand-new chat has no messages, so it has no row: the List reports an
    /// empty selection for a tag it can't find. Clearing there would close the
    /// chat the user just created.
    func testOpenAction_emptySelectionKeepsAnUnlistedChat() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.openAction(
                newSelection: [],
                openConversationID: openID,
                openConversationIsListed: false
            ),
            .keep
        )
    }

    func testOpenAction_emptySelectionWithNothingOpenIsANoop() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.openAction(
                newSelection: [],
                openConversationID: nil,
                openConversationIsListed: false
            ),
            .keep
        )
    }

    // MARK: - highlightedIDs

    func testHighlightedIDs_fallsBackToTheOpenChat() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.highlightedIDs(
                explicitSelection: [],
                openConversationID: openID,
                openConversationIsListed: true
            ),
            [openID]
        )
    }

    func testHighlightedIDs_doesNotHighlightAnUnlistedOpenChat() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.highlightedIDs(
                explicitSelection: [],
                openConversationID: openID,
                openConversationIsListed: false
            ),
            []
        )
    }

    func testHighlightedIDs_explicitSelectionWins() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.highlightedIDs(
                explicitSelection: [otherID],
                openConversationID: openID,
                openConversationIsListed: true
            ),
            [otherID]
        )
    }

    // MARK: - toggled / range

    func testToggledAddsThenRemoves() {
        let added = ChatsSidebarSelectionSupport.toggled([], id: openID)
        XCTAssertEqual(added, [openID])
        XCTAssertEqual(ChatsSidebarSelectionSupport.toggled(added, id: openID), [])
    }

    func testRangeSelectionCoversBothDirections() {
        let ids = (0..<5).map { _ in UUID() }

        XCTAssertEqual(
            ChatsSidebarSelectionSupport.rangeSelection(from: ids[1], to: ids[3], in: ids),
            Set(ids[1...3])
        )
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.rangeSelection(from: ids[3], to: ids[1], in: ids),
            Set(ids[1...3])
        )
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.rangeSelection(from: ids[2], to: ids[2], in: ids),
            [ids[2]]
        )
    }

    func testRangeSelectionWithoutAnchorOrOffscreenAnchorReturnsNil() {
        let ids = (0..<3).map { _ in UUID() }
        XCTAssertNil(ChatsSidebarSelectionSupport.rangeSelection(from: nil, to: ids[0], in: ids))
        XCTAssertNil(ChatsSidebarSelectionSupport.rangeSelection(from: UUID(), to: ids[0], in: ids))
    }

    // MARK: - select all

    func testSelectAllTogglesOnlyTheVisibleRows() {
        let visible = (0..<3).map { _ in UUID() }
        let hidden = UUID()

        let selectedAll = ChatsSidebarSelectionSupport.selectAllToggled([hidden], visibleIDs: visible)
        XCTAssertEqual(selectedAll, Set(visible).union([hidden]))
        XCTAssertTrue(ChatsSidebarSelectionSupport.allVisibleSelected(selectedAll, visibleIDs: visible))

        // Deselecting keeps rows the search filter is currently hiding.
        let deselected = ChatsSidebarSelectionSupport.selectAllToggled(selectedAll, visibleIDs: visible)
        XCTAssertEqual(deselected, [hidden])
        XCTAssertFalse(ChatsSidebarSelectionSupport.allVisibleSelected(deselected, visibleIDs: visible))
    }

    func testAllVisibleSelectedIsFalseWithNoRows() {
        XCTAssertFalse(ChatsSidebarSelectionSupport.allVisibleSelected([openID], visibleIDs: []))
    }

    // MARK: - star direction

    func testShouldStarSelection() {
        XCTAssertTrue(ChatsSidebarSelectionSupport.shouldStarSelection(starredFlags: [true, false]))
        XCTAssertTrue(ChatsSidebarSelectionSupport.shouldStarSelection(starredFlags: [false]))
        XCTAssertTrue(ChatsSidebarSelectionSupport.shouldStarSelection(starredFlags: []))
        XCTAssertFalse(ChatsSidebarSelectionSupport.shouldStarSelection(starredFlags: [true, true]))
    }

    // MARK: - ordered selection

    func testOrderedSelectionKeepsDisplayOrderAndDropsMissingIDs() {
        struct Row { let id: UUID }
        let rows = (0..<4).map { _ in Row(id: UUID()) }
        let deletedID = UUID()

        let resolved = ChatsSidebarSelectionSupport.orderedSelection(
            from: rows,
            matching: [rows[3].id, rows[0].id, deletedID],
            id: \.id
        )

        XCTAssertEqual(resolved.map(\.id), [rows[0].id, rows[3].id])
    }

    func testOrderedSelectionIsEmptyForAnEmptySet() {
        struct Row { let id: UUID }
        XCTAssertTrue(
            ChatsSidebarSelectionSupport.orderedSelection(
                from: [Row(id: UUID())],
                matching: [],
                id: \.id
            ).isEmpty
        )
    }

    // MARK: - copy

    func testCopyPluralization() {
        XCTAssertEqual(ChatsSidebarSelectionSupport.selectionSummary(count: 1), "1 selected")
        XCTAssertEqual(ChatsSidebarSelectionSupport.selectionSummary(count: 4), "4 selected")

        XCTAssertEqual(ChatsSidebarSelectionSupport.deleteTitle(count: 1), "Delete Chat")
        XCTAssertEqual(ChatsSidebarSelectionSupport.deleteTitle(count: 3), "Delete 3 Chats")

        XCTAssertEqual(ChatsSidebarSelectionSupport.starTitle(shouldStar: true, count: 1), "Star Chat")
        XCTAssertEqual(ChatsSidebarSelectionSupport.starTitle(shouldStar: false, count: 2), "Unstar 2 Chats")

        XCTAssertEqual(ChatsSidebarSelectionSupport.deleteConfirmationTitle(count: 1), "Delete chat?")
        XCTAssertEqual(ChatsSidebarSelectionSupport.deleteConfirmationTitle(count: 7), "Delete 7 chats?")
    }

    func testDeleteConfirmationMessageNamesUpToThreeChats() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.deleteConfirmationMessage(titles: ["Alpha"]),
            "This will permanently delete \u{201C}Alpha\u{201D}."
        )
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.deleteConfirmationMessage(titles: ["Alpha", "Beta"]),
            "This will permanently delete \u{201C}Alpha\u{201D}, \u{201C}Beta\u{201D}."
        )
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.deleteConfirmationMessage(titles: ["A", "B", "C", "D"]),
            "This will permanently delete 4 chats."
        )
    }

    /// The dialog's message builder re-runs as it dismisses, after the confirm
    /// action emptied the pending list.
    func testDeleteConfirmationMessageSurvivesAnEmptyList() {
        XCTAssertEqual(
            ChatsSidebarSelectionSupport.deleteConfirmationMessage(titles: []),
            "This will permanently delete \u{201C}\u{201D}."
        )
    }
}
