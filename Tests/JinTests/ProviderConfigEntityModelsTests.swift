import XCTest
@testable import Jin

final class ProviderConfigEntityModelsTests: XCTestCase {
    func testEnabledModelsFiltersDisabledEntries() throws {
        let models = [
            ModelInfo(id: "a", name: "A", capabilities: [.streaming], contextWindow: 1024, isEnabled: true),
            ModelInfo(id: "b", name: "B", capabilities: [.streaming], contextWindow: 1024, isEnabled: false),
        ]
        let data = try JSONEncoder().encode(models)
        let provider = ProviderConfigEntity(
            id: "provider-a",
            name: "Provider A",
            typeRaw: ProviderType.openai.rawValue,
            modelsData: data
        )

        XCTAssertEqual(provider.allModels.count, 2)
        XCTAssertEqual(provider.enabledModels.count, 1)
        XCTAssertEqual(provider.enabledModels.first?.id, "a")
    }

    func testAllModelsCacheInvalidatesAfterModelsDataChange() throws {
        let initialModels = [
            ModelInfo(id: "old-model", name: "Old", capabilities: [.streaming], contextWindow: 1024, isEnabled: true),
        ]
        let updatedModels = [
            ModelInfo(id: "new-model", name: "New", capabilities: [.streaming], contextWindow: 2048, isEnabled: false),
        ]

        let provider = ProviderConfigEntity(
            id: "provider-b",
            name: "Provider B",
            typeRaw: ProviderType.openai.rawValue,
            modelsData: try JSONEncoder().encode(initialModels)
        )

        XCTAssertEqual(provider.allModels.first?.id, "old-model")
        XCTAssertEqual(provider.enabledModels.count, 1)

        provider.modelsData = try JSONEncoder().encode(updatedModels)

        XCTAssertEqual(provider.allModels.first?.id, "new-model")
        XCTAssertEqual(provider.enabledModels.count, 0)
    }

    func testClaudeManagedAgentsExposeSyntheticSelectableModelWithoutLocalCatalog() throws {
        let provider = ProviderConfigEntity(
            id: "claude-managed",
            name: "Claude Managed",
            typeRaw: ProviderType.claudeManagedAgents.rawValue,
            apiKeyKeychainID: nil,
            modelsData: try JSONEncoder().encode([
                ModelInfo(id: "ignored", name: "Ignored", capabilities: [.streaming], contextWindow: 1024, isEnabled: true),
            ])
        )
        provider.claudeManagedDefaultAgentID = "agent_123"
        provider.claudeManagedDefaultEnvironmentID = "env_456"
        provider.claudeManagedDefaultAgentDisplayName = "Build Agent"
        provider.claudeManagedDefaultAgentModelID = "claude-opus-4-6"

        XCTAssertTrue(provider.allModels.isEmpty)
        XCTAssertTrue(provider.enabledModels.isEmpty)
        XCTAssertEqual(provider.selectableModels.count, 1)
        XCTAssertEqual(provider.selectableModels.first?.name, "Build Agent")
        XCTAssertEqual(
            provider.selectableModels.first?.id,
            ClaudeManagedAgentRuntime.syntheticThreadModelID(
                providerID: "claude-managed",
                agentID: "agent_123",
                environmentID: "env_456"
            )
        )
    }
}
