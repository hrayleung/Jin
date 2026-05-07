import XCTest
@testable import Jin

final class ClaudeManagedAgentSessionSettingsSheetSupportTests: XCTestCase {
    func testUseProviderDefaultsRequiresAtLeastOneDefaultID() {
        XCTAssertTrue(
            ClaudeManagedAgentSessionSettingsSheetSupport.useProviderDefaultsDisabled(
                providerDefaultAgentID: "",
                providerDefaultEnvironmentID: ""
            )
        )
        XCTAssertTrue(
            ClaudeManagedAgentSessionSettingsSheetSupport.useProviderDefaultsDisabled(
                providerDefaultAgentID: " \n ",
                providerDefaultEnvironmentID: ""
            )
        )
        XCTAssertFalse(
            ClaudeManagedAgentSessionSettingsSheetSupport.useProviderDefaultsDisabled(
                providerDefaultAgentID: "agent_1",
                providerDefaultEnvironmentID: ""
            )
        )
        XCTAssertFalse(
            ClaudeManagedAgentSessionSettingsSheetSupport.useProviderDefaultsDisabled(
                providerDefaultAgentID: "",
                providerDefaultEnvironmentID: "env_1"
            )
        )
    }

    func testProviderDefaultSummaryRowsPreferDisplayNamesAndPreserveCurrentEmptyRowBehavior() {
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.providerDefaultSummaryRows(
                providerDefaultAgentID: "",
                providerDefaultEnvironmentID: "",
                providerDefaultAgentDisplayName: "Build Agent",
                providerDefaultEnvironmentDisplayName: "macOS Workspace"
            ),
            []
        )
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.providerDefaultSummaryRows(
                providerDefaultAgentID: "agent_1",
                providerDefaultEnvironmentID: "",
                providerDefaultAgentDisplayName: "Build Agent",
                providerDefaultEnvironmentDisplayName: ""
            ),
            [
                .init(title: "Agent", value: "Build Agent"),
                .init(title: "Environment", value: "")
            ]
        )
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.providerDefaultSummaryRows(
                providerDefaultAgentID: "agent_1",
                providerDefaultEnvironmentID: "env_1",
                providerDefaultAgentDisplayName: "",
                providerDefaultEnvironmentDisplayName: "macOS Workspace"
            ),
            [
                .init(title: "Agent", value: "agent_1"),
                .init(title: "Environment", value: "macOS Workspace")
            ]
        )
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.providerDefaultSummaryRows(
                providerDefaultAgentID: " agent_1 ",
                providerDefaultEnvironmentID: " env_1 ",
                providerDefaultAgentDisplayName: " \n ",
                providerDefaultEnvironmentDisplayName: " macOS Workspace "
            ),
            [
                .init(title: "Agent", value: "agent_1"),
                .init(title: "Environment", value: "macOS Workspace")
            ]
        )
    }

    func testCustomLabelsUseTrimmedDrafts() {
        XCTAssertFalse(
            ClaudeManagedAgentSessionSettingsSheetSupport.hasCustomLabels(
                agentDisplayNameDraft: " \n ",
                environmentDisplayNameDraft: ""
            )
        )
        XCTAssertTrue(
            ClaudeManagedAgentSessionSettingsSheetSupport.hasCustomLabels(
                agentDisplayNameDraft: " Build Agent ",
                environmentDisplayNameDraft: ""
            )
        )
        XCTAssertTrue(
            ClaudeManagedAgentSessionSettingsSheetSupport.hasCustomLabels(
                agentDisplayNameDraft: "",
                environmentDisplayNameDraft: " macOS Workspace "
            )
        )
    }

    func testMatchedPickerIDsOnlyReturnCatalogMatches() {
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.matchedAgentID(
                agentIDDraft: "agent_1",
                availableAgents: [agent()]
            ),
            "agent_1"
        )
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.matchedAgentID(
                agentIDDraft: " agent_1 ",
                availableAgents: [agent()]
            ),
            ""
        )
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.matchedEnvironmentID(
                environmentIDDraft: "env_1",
                availableEnvironments: [environment()]
            ),
            "env_1"
        )
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.matchedEnvironmentID(
                environmentIDDraft: "env_missing",
                availableEnvironments: [environment()]
            ),
            ""
        )
    }

    func testAgentSelectionUpdateClearsCustomPickerChoiceAndUsesKnownAgent() {
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.agentSelectionUpdate(
                selectedID: " \n ",
                availableAgents: [agent()]
            ),
            .init(idDraft: "", displayNameDraft: nil)
        )
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.agentSelectionUpdate(
                selectedID: " agent_1 ",
                availableAgents: [agent()]
            ),
            .init(idDraft: "agent_1", displayNameDraft: "Build Agent")
        )
        XCTAssertNil(
            ClaudeManagedAgentSessionSettingsSheetSupport.agentSelectionUpdate(
                selectedID: "agent_missing",
                availableAgents: [agent()]
            )
        )
    }

    func testEnvironmentSelectionUpdateClearsCustomPickerChoiceAndUsesKnownEnvironment() {
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.environmentSelectionUpdate(
                selectedID: "",
                availableEnvironments: [environment()]
            ),
            .init(idDraft: "", displayNameDraft: nil)
        )
        XCTAssertEqual(
            ClaudeManagedAgentSessionSettingsSheetSupport.environmentSelectionUpdate(
                selectedID: " env_1 ",
                availableEnvironments: [environment()]
            ),
            .init(idDraft: "env_1", displayNameDraft: "macOS Workspace")
        )
        XCTAssertNil(
            ClaudeManagedAgentSessionSettingsSheetSupport.environmentSelectionUpdate(
                selectedID: "env_missing",
                availableEnvironments: [environment()]
            )
        )
    }

    private func agent() -> ClaudeManagedAgentDescriptor {
        ClaudeManagedAgentDescriptor(id: "agent_1", name: "Build Agent")
    }

    private func environment() -> ClaudeManagedEnvironmentDescriptor {
        ClaudeManagedEnvironmentDescriptor(id: "env_1", name: "macOS Workspace")
    }
}
