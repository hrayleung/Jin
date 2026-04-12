import XCTest
@testable import Jin

final class ClaudeManagedAgentRuntimeTests: XCTestCase {
    func testResolvedDisplayNamePrefersAgentIdentityOverManagedModelName() {
        var controls = GenerationControls()
        controls.claudeManagedAgentID = "agent_123"
        controls.claudeManagedAgentModelDisplayName = "Claude Sonnet 4.6"

        let displayName = ClaudeManagedAgentRuntime.resolvedDisplayName(
            threadModelID: ClaudeManagedAgentRuntime.syntheticThreadModelID(
                providerID: "managed-provider",
                agentID: controls.claudeManagedAgentID,
                environmentID: "env_456"
            ),
            controls: controls
        )

        XCTAssertEqual(displayName, "agent_123")
    }

    func testResolvedDisplayNameUsesConfiguredAgentNameWhenAvailable() {
        var controls = GenerationControls()
        controls.claudeManagedAgentID = "agent_123"
        controls.claudeManagedAgentDisplayName = "Build Agent"
        controls.claudeManagedAgentModelDisplayName = "Claude Sonnet 4.6"

        let displayName = ClaudeManagedAgentRuntime.resolvedDisplayName(
            threadModelID: "claude-managed::managed-provider::agent_123::env_456",
            controls: controls
        )

        XCTAssertEqual(displayName, "Build Agent")
    }
}
