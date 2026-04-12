import XCTest
@testable import Jin

final class ClaudeManagedAgentResolutionSupportTests: XCTestCase {
    func testCanonicalManagedThreadModelIDPreservesRequestedSyntheticDescriptor() {
        var fallbackControls = GenerationControls()
        fallbackControls.claudeManagedAgentID = "agent_default"
        fallbackControls.claudeManagedEnvironmentID = "env_default"

        let requestedModelID = ClaudeManagedAgentRuntime.syntheticThreadModelID(
            providerID: "managed-provider",
            agentID: "agent_selected",
            environmentID: "env_selected"
        )

        let resolved = ClaudeManagedAgentResolutionSupport.canonicalManagedThreadModelID(
            providerID: "managed-provider",
            requestedModelID: requestedModelID,
            fallbackControls: fallbackControls,
            storedThreadControls: nil,
            applyProviderDefaults: { controls in
                if controls.claudeManagedAgentID == nil {
                    controls.claudeManagedAgentID = "agent_default"
                }
                if controls.claudeManagedEnvironmentID == nil {
                    controls.claudeManagedEnvironmentID = "env_default"
                }
            }
        )

        XCTAssertEqual(resolved, requestedModelID)
    }

    func testCanonicalManagedThreadModelIDUsesStoredControlsForLegacyThreadModelID() {
        var storedThreadControls = GenerationControls()
        storedThreadControls.claudeManagedAgentID = "agent_thread"
        storedThreadControls.claudeManagedEnvironmentID = "env_thread"

        let resolved = ClaudeManagedAgentResolutionSupport.canonicalManagedThreadModelID(
            providerID: "managed-provider",
            requestedModelID: "claude-sonnet-4-6",
            fallbackControls: GenerationControls(),
            storedThreadControls: storedThreadControls,
            applyProviderDefaults: { _ in }
        )

        XCTAssertEqual(
            resolved,
            ClaudeManagedAgentRuntime.syntheticThreadModelID(
                providerID: "managed-provider",
                agentID: "agent_thread",
                environmentID: "env_thread"
            )
        )
    }

    func testResolvedConversationDisplayNamePrefersStoredControlsOverCurrentProviderDefaults() {
        var storedControls = GenerationControls()
        storedControls.claudeManagedAgentID = "agent_old"
        storedControls.claudeManagedAgentDisplayName = "Build Agent"

        let displayName = ClaudeManagedAgentResolutionSupport.resolvedConversationDisplayName(
            threadModelID: ClaudeManagedAgentRuntime.syntheticThreadModelID(
                providerID: "managed-provider",
                agentID: "agent_new",
                environmentID: "env_new"
            ),
            storedControls: storedControls,
            applyProviderDefaults: { controls in
                if controls.claudeManagedAgentID == nil {
                    controls.claudeManagedAgentID = "agent_default"
                }
                if controls.claudeManagedAgentDisplayName == nil {
                    controls.claudeManagedAgentDisplayName = "Provider Default"
                }
            }
        )

        XCTAssertEqual(displayName, "Build Agent")
    }

    func testResolvedConversationDisplayNameFallsBackToProviderDefaultsWhenStoredControlsMissing() {
        let displayName = ClaudeManagedAgentResolutionSupport.resolvedConversationDisplayName(
            threadModelID: ClaudeManagedAgentRuntime.syntheticThreadModelID(
                providerID: "managed-provider",
                agentID: nil,
                environmentID: nil
            ),
            storedControls: nil,
            applyProviderDefaults: { controls in
                controls.claudeManagedAgentDisplayName = "Provider Default"
            }
        )

        XCTAssertEqual(displayName, "Provider Default")
    }
}
