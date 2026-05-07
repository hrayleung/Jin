import XCTest
@testable import Jin

final class ClaudeManagedDefaultsFormSupportTests: XCTestCase {
    func testRefreshIsDisabledWithoutAPIKeyOrWhileRefreshing() {
        XCTAssertTrue(
            ClaudeManagedDefaultsFormSupport.isRefreshDisabled(
                apiKey: " \n ",
                isRefreshing: false
            )
        )
        XCTAssertTrue(
            ClaudeManagedDefaultsFormSupport.isRefreshDisabled(
                apiKey: "sk-ant",
                isRefreshing: true
            )
        )
        XCTAssertFalse(
            ClaudeManagedDefaultsFormSupport.isRefreshDisabled(
                apiKey: " sk-ant ",
                isRefreshing: false
            )
        )
    }

    func testAgentDefaultsUpdateClearsBlankSelectionAndUsesKnownDescriptor() {
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.agentDefaultsUpdate(
                agentID: " \n ",
                availableAgents: [agent()],
                preserveSelectionIfMissing: false
            ),
            .init(id: nil, displayName: nil, modelID: nil, modelDisplayName: nil)
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.agentDefaultsUpdate(
                agentID: " agent_1 ",
                availableAgents: [agent()],
                preserveSelectionIfMissing: false
            ),
            .init(
                id: "agent_1",
                displayName: "Build Agent",
                modelID: "claude-sonnet-4-6",
                modelDisplayName: "Claude Sonnet 4.6"
            )
        )
    }

    func testAgentDefaultsUpdateHandlesMissingDescriptorByMode() {
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.agentDefaultsUpdate(
                agentID: " agent_manual ",
                availableAgents: [agent()],
                preserveSelectionIfMissing: false
            ),
            .init(id: "agent_manual", displayName: nil, modelID: nil, modelDisplayName: nil)
        )
        XCTAssertNil(
            ClaudeManagedDefaultsFormSupport.agentDefaultsUpdate(
                agentID: " agent_manual ",
                availableAgents: [agent()],
                preserveSelectionIfMissing: true
            )
        )
    }

    func testEnvironmentDefaultsUpdateClearsBlankSelectionAndUsesKnownDescriptor() {
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.environmentDefaultsUpdate(
                environmentID: " \n ",
                availableEnvironments: [environment()],
                preserveSelectionIfMissing: false
            ),
            .init(id: nil, displayName: nil)
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.environmentDefaultsUpdate(
                environmentID: " env_1 ",
                availableEnvironments: [environment()],
                preserveSelectionIfMissing: false
            ),
            .init(id: "env_1", displayName: "macOS Workspace")
        )
    }

    func testEnvironmentDefaultsUpdateHandlesMissingDescriptorByMode() {
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.environmentDefaultsUpdate(
                environmentID: " env_manual ",
                availableEnvironments: [environment()],
                preserveSelectionIfMissing: false
            ),
            .init(id: "env_manual", displayName: nil)
        )
        XCTAssertNil(
            ClaudeManagedDefaultsFormSupport.environmentDefaultsUpdate(
                environmentID: " env_manual ",
                availableEnvironments: [environment()],
                preserveSelectionIfMissing: true
            )
        )
    }

    func testManualPickerFallbackAppearsOnlyForMissingSelectedID() {
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.manualPickerFallbackID(
                selectedID: " agent_manual ",
                availableIDs: ["agent_1", "agent_2"]
            ),
            "agent_manual"
        )
        XCTAssertNil(
            ClaudeManagedDefaultsFormSupport.manualPickerFallbackID(
                selectedID: "agent_1",
                availableIDs: ["agent_1", "agent_2"]
            )
        )
        XCTAssertNil(
            ClaudeManagedDefaultsFormSupport.manualPickerFallbackID(
                selectedID: " \n ",
                availableIDs: ["agent_1", "agent_2"]
            )
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.manualPickerFallbackLabel(for: "agent_manual"),
            "Manual ID (agent_manual)"
        )
    }

    func testSelectedDetailTextOnlyAppearsAfterCatalogLoads() {
        XCTAssertNil(
            ClaudeManagedDefaultsFormSupport.selectedAgentDetailText(
                hasAvailableAgents: false,
                displayName: "Build Agent",
                selectedID: "agent_1"
            )
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.selectedAgentDetailText(
                hasAvailableAgents: true,
                displayName: " Build Agent ",
                selectedID: "agent_1"
            ),
            "Build Agent"
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.selectedAgentDetailText(
                hasAvailableAgents: true,
                displayName: nil,
                selectedID: "agent_1"
            ),
            "agent_1"
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.selectedAgentDetailText(
                hasAvailableAgents: true,
                displayName: nil,
                selectedID: nil
            ),
            "No agent selected"
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.selectedEnvironmentDetailText(
                hasAvailableEnvironments: true,
                displayName: " macOS Workspace ",
                selectedID: "env_1"
            ),
            "macOS Workspace"
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.selectedEnvironmentDetailText(
                hasAvailableEnvironments: true,
                displayName: nil,
                selectedID: nil
            ),
            "No environment selected"
        )
    }

    func testManualDraftButtonEligibilityUsesTrimmedDrafts() {
        XCTAssertTrue(
            ClaudeManagedDefaultsFormSupport.canApplyDraft(
                " agent_new ",
                currentID: "agent_old"
            )
        )
        XCTAssertFalse(
            ClaudeManagedDefaultsFormSupport.canApplyDraft(
                " agent_old ",
                currentID: "agent_old"
            )
        )
        XCTAssertFalse(
            ClaudeManagedDefaultsFormSupport.canApplyDraft(
                " \n ",
                currentID: "agent_old"
            )
        )

        XCTAssertTrue(
            ClaudeManagedDefaultsFormSupport.canClearDraft(
                "",
                currentID: "agent_old"
            )
        )
        XCTAssertTrue(
            ClaudeManagedDefaultsFormSupport.canClearDraft(
                " agent_new ",
                currentID: nil
            )
        )
        XCTAssertFalse(
            ClaudeManagedDefaultsFormSupport.canClearDraft(
                " \n ",
                currentID: nil
            )
        )
    }

    func testSelectedSummaryLinesIncludeConfiguredIDsAndRemoteModel() {
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.selectedSummaryLines(
                agentID: " agent_1 ",
                environmentID: " env_1 ",
                agentModelID: " claude-sonnet-4-6 ",
                agentModelDisplayName: " Claude Sonnet 4.6 "
            ),
            [
                .init(kind: .agentID, text: "Agent ID: agent_1"),
                .init(kind: .environmentID, text: "Environment ID: env_1"),
                .init(kind: .remoteModel, text: "Remote model: Claude Sonnet 4.6")
            ]
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.selectedSummaryLines(
                agentID: "agent_1",
                environmentID: nil,
                agentModelID: "claude-sonnet-4-6",
                agentModelDisplayName: nil
            ),
            [
                .init(kind: .agentID, text: "Agent ID: agent_1"),
                .init(kind: .remoteModel, text: "Remote model: claude-sonnet-4-6")
            ]
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.selectedSummaryLines(
                agentID: nil,
                environmentID: nil,
                agentModelID: "claude-sonnet-4-6",
                agentModelDisplayName: "Claude Sonnet 4.6"
            ),
            []
        )
    }

    func testManualHintAppearsWhenEitherCatalogIsMissing() {
        XCTAssertTrue(
            ClaudeManagedDefaultsFormSupport.shouldShowManualHint(
                hasAvailableAgents: false,
                hasAvailableEnvironments: true
            )
        )
        XCTAssertTrue(
            ClaudeManagedDefaultsFormSupport.shouldShowManualHint(
                hasAvailableAgents: true,
                hasAvailableEnvironments: false
            )
        )
        XCTAssertFalse(
            ClaudeManagedDefaultsFormSupport.shouldShowManualHint(
                hasAvailableAgents: true,
                hasAvailableEnvironments: true
            )
        )
        XCTAssertEqual(
            ClaudeManagedDefaultsFormSupport.manualHintText,
            "If Anthropic does not return lists for your workspace, enter the Agent ID and Environment ID manually here. Those IDs will still seed new chat threads."
        )
    }

    private func agent() -> ClaudeManagedAgentDescriptor {
        ClaudeManagedAgentDescriptor(
            id: "agent_1",
            name: "Build Agent",
            modelID: "claude-sonnet-4-6",
            modelDisplayName: "Claude Sonnet 4.6"
        )
    }

    private func environment() -> ClaudeManagedEnvironmentDescriptor {
        ClaudeManagedEnvironmentDescriptor(id: "env_1", name: "macOS Workspace")
    }
}
