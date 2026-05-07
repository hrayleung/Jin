import XCTest
@testable import Jin

final class ChatClaudeManagedAgentSessionSupportTests: XCTestCase {
    func testPreparedSettingsDraftPrefersExplicitIDsAndResolvedNames() {
        var controls = GenerationControls()
        controls.claudeManagedAgentID = "agent_thread"
        controls.claudeManagedEnvironmentID = "env_thread"

        let draft = ChatClaudeManagedAgentSessionSupport.preparedSettingsDraft(
            controls: controls,
            providerDefaults: providerDefaults(),
            resolvedAgentDisplayName: "Thread Agent",
            resolvedEnvironmentDisplayName: "Thread Environment"
        )

        XCTAssertEqual(
            draft,
            ChatClaudeManagedAgentSessionSupport.SettingsDraft(
                agentID: "agent_thread",
                environmentID: "env_thread",
                agentDisplayName: "Thread Agent",
                environmentDisplayName: "Thread Environment"
            )
        )
    }

    func testPreparedSettingsDraftFallsBackToProviderDefaults() {
        let draft = ChatClaudeManagedAgentSessionSupport.preparedSettingsDraft(
            controls: GenerationControls(),
            providerDefaults: providerDefaults(),
            resolvedAgentDisplayName: "Default Agent",
            resolvedEnvironmentDisplayName: nil
        )

        XCTAssertEqual(
            draft,
            ChatClaudeManagedAgentSessionSupport.SettingsDraft(
                agentID: "agent_default",
                environmentID: "env_default",
                agentDisplayName: "Default Agent",
                environmentDisplayName: "Default Environment"
            )
        )
    }

    func testSettingsDraftUsingProviderDefaultsCopiesNormalizedValues() {
        let draft = ChatClaudeManagedAgentSessionSupport.settingsDraftUsingProviderDefaults(
            providerDefaults()
        )

        XCTAssertEqual(
            draft,
            ChatClaudeManagedAgentSessionSupport.SettingsDraft(
                agentID: "agent_default",
                environmentID: "env_default",
                agentDisplayName: "Default Agent",
                environmentDisplayName: "Default Environment"
            )
        )
    }

    func testSettingsDraftFillingResourceNamesOnlyFillsBlankLabels() {
        let draft = ChatClaudeManagedAgentSessionSupport.settingsDraftFillingResourceNames(
            ChatClaudeManagedAgentSessionSupport.SettingsDraft(
                agentID: "agent_1",
                environmentID: "env_1",
                agentDisplayName: "",
                environmentDisplayName: "Custom Environment"
            ),
            availableAgents: [
                ClaudeManagedAgentDescriptor(id: "agent_1", name: "Build Agent")
            ],
            availableEnvironments: [
                ClaudeManagedEnvironmentDescriptor(id: "env_1", name: "Remote Workspace")
            ]
        )

        XCTAssertEqual(draft.agentDisplayName, "Build Agent")
        XCTAssertEqual(draft.environmentDisplayName, "Custom Environment")
    }

    func testSortedAgentsUsesLocalizedStandardNameOrder() {
        let agents = ChatClaudeManagedAgentSessionSupport.sortedAgents([
            ClaudeManagedAgentDescriptor(id: "agent_10", name: "Agent 10"),
            ClaudeManagedAgentDescriptor(id: "agent_2", name: "Agent 2"),
            ClaudeManagedAgentDescriptor(id: "agent_1", name: "Agent 1")
        ])

        XCTAssertEqual(agents.map(\.id), ["agent_1", "agent_2", "agent_10"])
    }

    func testSortedEnvironmentsUsesLocalizedStandardNameOrder() {
        let environments = ChatClaudeManagedAgentSessionSupport.sortedEnvironments([
            ClaudeManagedEnvironmentDescriptor(id: "env_10", name: "Workspace 10"),
            ClaudeManagedEnvironmentDescriptor(id: "env_2", name: "Workspace 2"),
            ClaudeManagedEnvironmentDescriptor(id: "env_1", name: "Workspace 1")
        ])

        XCTAssertEqual(environments.map(\.id), ["env_1", "env_2", "env_10"])
    }

    func testAgentSelectionAppliesDescriptorAndClearsSessionWhenIdentityChanges() {
        var currentControls = GenerationControls()
        currentControls.claudeManagedAgentID = "agent_old"
        currentControls.claudeManagedEnvironmentID = "env_1"
        currentControls.claudeManagedSessionID = "session_1"
        currentControls.claudeManagedSessionModelID = "claude-sonnet-4-6"
        currentControls.claudeManagedPendingCustomToolResults = [
            pendingToolResult()
        ]

        let update = ChatClaudeManagedAgentSessionSupport.controlsApplyingAgentSelection(
            ClaudeManagedAgentDescriptor(
                id: "agent_new",
                name: "Build Agent",
                modelID: "claude-opus-4-6",
                modelDisplayName: "Claude Opus 4.6"
            ),
            currentControls: currentControls,
            resolveControls: { $0 }
        )

        XCTAssertTrue(update.didChangeIdentity)
        XCTAssertEqual(update.controls.claudeManagedAgentID, "agent_new")
        XCTAssertEqual(update.controls.claudeManagedEnvironmentID, "env_1")
        XCTAssertEqual(update.controls.claudeManagedAgentDisplayName, "Build Agent")
        XCTAssertEqual(update.controls.claudeManagedAgentModelID, "claude-opus-4-6")
        XCTAssertEqual(update.controls.claudeManagedAgentModelDisplayName, "Claude Opus 4.6")
        XCTAssertNil(update.controls.claudeManagedSessionID)
        XCTAssertNil(update.controls.claudeManagedSessionModelID)
        XCTAssertTrue(update.controls.claudeManagedPendingCustomToolResults.isEmpty)
        XCTAssertEqual(update.resolvedControls.claudeManagedAgentID, "agent_new")
    }

    func testAgentSelectionPreservesSessionWhenIdentityDoesNotChange() {
        var currentControls = GenerationControls()
        currentControls.claudeManagedAgentID = "agent_1"
        currentControls.claudeManagedEnvironmentID = "env_1"
        currentControls.claudeManagedSessionID = "session_1"
        currentControls.claudeManagedSessionModelID = "claude-sonnet-4-6"

        let update = ChatClaudeManagedAgentSessionSupport.controlsApplyingAgentSelection(
            ClaudeManagedAgentDescriptor(
                id: "agent_1",
                name: "Renamed Agent",
                modelID: "claude-opus-4-6"
            ),
            currentControls: currentControls,
            resolveControls: { $0 }
        )

        XCTAssertFalse(update.didChangeIdentity)
        XCTAssertEqual(update.controls.claudeManagedAgentID, "agent_1")
        XCTAssertEqual(update.controls.claudeManagedAgentDisplayName, "Renamed Agent")
        XCTAssertEqual(update.controls.claudeManagedAgentModelID, "claude-opus-4-6")
        XCTAssertEqual(update.controls.claudeManagedSessionID, "session_1")
        XCTAssertEqual(update.controls.claudeManagedSessionModelID, "claude-sonnet-4-6")
    }

    func testControlUpdateComparesResolvedProviderDefaultIdentity() {
        var currentControls = GenerationControls()
        currentControls.claudeManagedSessionID = "session_1"

        var updatedControls = currentControls
        updatedControls.claudeManagedEnvironmentID = "env_override"

        let update = ChatClaudeManagedAgentSessionSupport.controlUpdate(
            currentControls: currentControls,
            updatedControls: updatedControls,
            resolveControls: { controls in
                var resolved = controls
                if resolved.claudeManagedAgentID == nil {
                    resolved.claudeManagedAgentID = "agent_default"
                }
                if resolved.claudeManagedEnvironmentID == nil {
                    resolved.claudeManagedEnvironmentID = "env_default"
                }
                return resolved
            }
        )

        XCTAssertTrue(update.didChangeIdentity)
        XCTAssertEqual(update.resolvedControls.claudeManagedAgentID, "agent_default")
        XCTAssertEqual(update.resolvedControls.claudeManagedEnvironmentID, "env_override")
        XCTAssertNil(update.controls.claudeManagedSessionID)
    }

    func testControlUpdatePreservesSessionWhenOnlyLabelsChange() {
        var currentControls = GenerationControls()
        currentControls.claudeManagedAgentID = "agent_1"
        currentControls.claudeManagedEnvironmentID = "env_1"
        currentControls.claudeManagedAgentDisplayName = "Old Name"
        currentControls.claudeManagedSessionID = "session_1"

        var updatedControls = currentControls
        updatedControls.claudeManagedAgentDisplayName = "New Name"
        updatedControls.claudeManagedEnvironmentDisplayName = "New Workspace"

        let update = ChatClaudeManagedAgentSessionSupport.controlUpdate(
            currentControls: currentControls,
            updatedControls: updatedControls,
            resolveControls: { $0 }
        )

        XCTAssertFalse(update.didChangeIdentity)
        XCTAssertEqual(update.controls.claudeManagedAgentDisplayName, "New Name")
        XCTAssertEqual(update.controls.claudeManagedEnvironmentDisplayName, "New Workspace")
        XCTAssertEqual(update.controls.claudeManagedSessionID, "session_1")
    }

    private func pendingToolResult() -> ClaudeManagedAgentPendingToolResult {
        ClaudeManagedAgentPendingToolResult(
            eventID: "evt_1",
            toolCallID: "tool_1",
            toolName: "bash",
            content: "ok",
            isError: false,
            sessionThreadID: "thread_1"
        )
    }

    private func providerDefaults() -> ChatClaudeManagedAgentSessionSupport.ProviderDefaults {
        ChatClaudeManagedAgentSessionSupport.ProviderDefaults(
            agentID: "agent_default",
            environmentID: "env_default",
            agentDisplayName: "Default Agent",
            environmentDisplayName: "Default Environment"
        )
    }
}
