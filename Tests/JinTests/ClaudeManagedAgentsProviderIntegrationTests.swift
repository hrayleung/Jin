import XCTest
@testable import Jin

final class ClaudeManagedAgentsProviderIntegrationTests: XCTestCase {
    func testClaudeManagedAgentsProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.claudeManagedAgents.displayName, "Claude Managed Agents")
        XCTAssertEqual(ProviderType.claudeManagedAgents.defaultBaseURL, "https://api.anthropic.com")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .claudeManagedAgents), "Claude")
    }

    func testProviderManagerCreatesClaudeManagedAgentsAdapter() async throws {
        let config = ProviderConfig(
            id: "claude-managed-agents",
            name: "Claude Managed Agents",
            type: .claudeManagedAgents,
            apiKey: "test-key",
            baseURL: ProviderType.claudeManagedAgents.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is ClaudeManagedAgentsAdapter)
    }

    func testDefaultProviderSeedsIncludeClaudeManagedAgentsWithoutLocalModelCatalog() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let provider = providers.first(where: { $0.type == .claudeManagedAgents }) else {
            return XCTFail("Expected Claude Managed Agents in default provider seeds.")
        }

        XCTAssertEqual(provider.id, "claude-managed-agents")
        XCTAssertEqual(provider.baseURL, ProviderType.claudeManagedAgents.defaultBaseURL)
        XCTAssertTrue(provider.models.isEmpty)
        XCTAssertFalse(provider.hasLocalModelCatalog)
    }

    func testClaudeManagedAgentsUsesAnthropicRequestShapeAndReasoningSupport() {
        XCTAssertEqual(
            ModelCapabilityRegistry.requestShape(for: .claudeManagedAgents, modelID: "claude-opus-4-6"),
            .anthropic
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(
                for: .claudeManagedAgents,
                modelID: "claude-opus-4-6"
            ),
            [.low, .medium, .high, .xhigh]
        )
    }

    func testClaudeManagedAgentsDisablesProviderNativeSearchAndCodeExecutionToggles() {
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsWebSearch(
                for: .claudeManagedAgents,
                modelID: "claude-sonnet-4-6"
            )
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsCodeExecution(
                for: .claudeManagedAgents,
                modelID: "claude-sonnet-4-6"
            )
        )
    }
}
