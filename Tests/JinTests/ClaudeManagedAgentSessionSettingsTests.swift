import XCTest
@testable import Jin

final class ClaudeManagedAgentSessionSettingsTests: XCTestCase {
    func testNormalizeClaudeManagedAgentSettingsPreservesManagedKeysForProvider() {
        var controls = GenerationControls()
        controls.claudeManagedAgentID = " agent_123 "
        controls.claudeManagedEnvironmentID = " env_456 "
        controls.claudeManagedAgentDisplayName = " Build Agent "
        controls.claudeManagedEnvironmentDisplayName = " macOS "
        controls.claudeManagedSessionID = " session_789 "
        controls.claudeManagedSessionModelID = " claude-sonnet-4-6 "
        controls.claudeManagedPendingCustomToolResults = [
            ClaudeManagedAgentPendingToolResult(
                eventID: "evt_1",
                toolCallID: "tool_1",
                toolName: "bash",
                content: "ok",
                isError: false,
                sessionThreadID: "thread_1"
            )
        ]

        controls.normalizeClaudeManagedAgentProviderSpecific(for: .claudeManagedAgents)

        XCTAssertEqual(controls.claudeManagedAgentID, "agent_123")
        XCTAssertEqual(controls.claudeManagedEnvironmentID, "env_456")
        XCTAssertEqual(controls.claudeManagedAgentDisplayName, "Build Agent")
        XCTAssertEqual(controls.claudeManagedEnvironmentDisplayName, "macOS")
        XCTAssertEqual(controls.claudeManagedSessionID, "session_789")
        XCTAssertEqual(controls.claudeManagedSessionModelID, "claude-sonnet-4-6")
        XCTAssertEqual(controls.claudeManagedPendingCustomToolResults.count, 1)
        XCTAssertEqual(controls.claudeManagedPendingCustomToolResults.first?.eventID, "evt_1")
        XCTAssertEqual(controls.claudeManagedPendingCustomToolResults.first?.sessionThreadID, "thread_1")
        XCTAssertEqual(controls.claudeManagedSessionOverrideCount, 2)
    }

    func testNormalizeClaudeManagedAgentSettingsRemovesKeysForOtherProviders() {
        var controls = GenerationControls(providerSpecific: [
            "claude_managed_agent_id": AnyCodable("agent_123"),
            "claude_managed_environment_id": AnyCodable("env_456"),
            "claude_managed_internal_session_id": AnyCodable("session_789"),
            "claude_managed_internal_session_model_id": AnyCodable("claude-sonnet-4-6")
        ])

        controls.normalizeClaudeManagedAgentProviderSpecific(for: .openai)

        XCTAssertTrue(controls.providerSpecific.isEmpty)
        XCTAssertNil(controls.claudeManagedAgentID)
        XCTAssertNil(controls.claudeManagedEnvironmentID)
        XCTAssertNil(controls.claudeManagedSessionID)
        XCTAssertNil(controls.claudeManagedSessionModelID)
    }

    func testClearClaudeManagedAgentSessionStatePreservesConfiguredIDs() {
        var controls = GenerationControls()
        controls.claudeManagedAgentID = "agent_123"
        controls.claudeManagedEnvironmentID = "env_456"
        controls.claudeManagedSessionID = "session_789"
        controls.claudeManagedSessionModelID = "claude-opus-4-6"
        controls.claudeManagedPendingCustomToolResults = [
            ClaudeManagedAgentPendingToolResult(
                eventID: "evt_1",
                toolCallID: "tool_1",
                toolName: "bash",
                content: "ok",
                isError: false,
                sessionThreadID: "thread_1"
            )
        ]

        controls.clearClaudeManagedAgentSessionState()

        XCTAssertEqual(controls.claudeManagedAgentID, "agent_123")
        XCTAssertEqual(controls.claudeManagedEnvironmentID, "env_456")
        XCTAssertNil(controls.claudeManagedSessionID)
        XCTAssertNil(controls.claudeManagedSessionModelID)
        XCTAssertTrue(controls.claudeManagedPendingCustomToolResults.isEmpty)
    }
}
