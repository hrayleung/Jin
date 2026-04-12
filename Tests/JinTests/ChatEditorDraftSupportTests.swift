import XCTest
@testable import Jin

final class ChatEditorDraftSupportTests: XCTestCase {
    func testManagedSelectionLabelAutoUpdatesWhenExistingLabelIsBlank() {
        XCTAssertTrue(
            ChatEditorDraftSupport.shouldAutoUpdateClaudeManagedSelectionLabel(
                existingLabel: "",
                previousSelectionID: "agent_old",
                availableLabelsByID: [
                    "agent_old": "Deep researcher",
                    "agent_new": "Stock & Investment Analyst"
                ],
                providerDefaultLabel: "Default agent"
            )
        )
    }

    func testManagedSelectionLabelAutoUpdatesWhenExistingLabelMatchesProviderDefault() {
        XCTAssertTrue(
            ChatEditorDraftSupport.shouldAutoUpdateClaudeManagedSelectionLabel(
                existingLabel: "Default agent",
                previousSelectionID: "agent_old",
                availableLabelsByID: [
                    "agent_old": "Deep researcher"
                ],
                providerDefaultLabel: "Default agent"
            )
        )
    }

    func testManagedSelectionLabelAutoUpdatesWhenExistingLabelMatchesPreviousSelectedAgentName() {
        XCTAssertTrue(
            ChatEditorDraftSupport.shouldAutoUpdateClaudeManagedSelectionLabel(
                existingLabel: "Deep researcher",
                previousSelectionID: "agent_old",
                availableLabelsByID: [
                    "agent_old": "Deep researcher",
                    "agent_new": "Stock & Investment Analyst"
                ],
                providerDefaultLabel: "Default agent"
            )
        )
    }

    func testManagedSelectionLabelPreservesCustomLabel() {
        XCTAssertFalse(
            ChatEditorDraftSupport.shouldAutoUpdateClaudeManagedSelectionLabel(
                existingLabel: "My custom label",
                previousSelectionID: "agent_old",
                availableLabelsByID: [
                    "agent_old": "Deep researcher",
                    "agent_new": "Stock & Investment Analyst"
                ],
                providerDefaultLabel: "Default agent"
            )
        )
    }
}
