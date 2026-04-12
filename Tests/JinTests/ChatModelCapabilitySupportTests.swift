import XCTest
@testable import Jin

final class ChatModelCapabilitySupportTests: XCTestCase {
    func testResolvedClaudeManagedAgentModelInfoUsesRuntimeSessionModelMetadata() throws {
        let provider = ProviderConfigEntity(
            id: "claude-managed",
            name: "Claude Managed",
            typeRaw: ProviderType.claudeManagedAgents.rawValue,
            modelsData: Data()
        )
        provider.claudeManagedDefaultAgentID = "agent_123"
        provider.claudeManagedDefaultEnvironmentID = "env_456"
        provider.claudeManagedDefaultAgentDisplayName = "Build Agent"
        provider.claudeManagedDefaultAgentModelID = "claude-opus-4-6"

        var threadControls = GenerationControls()
        threadControls.claudeManagedSessionModelID = "claude-sonnet-4-6"

        let threadModelID = ClaudeManagedAgentRuntime.syntheticThreadModelID(
            providerID: "claude-managed",
            agentID: "agent_123",
            environmentID: "env_456"
        )
        let resolved = try XCTUnwrap(
            ChatModelCapabilitySupport.resolvedClaudeManagedAgentModelInfo(
                threadModelID: threadModelID,
                providerEntity: provider,
                threadControls: threadControls
            )
        )
        let remoteModel = try XCTUnwrap(
            ModelCatalog.seededModels(for: .anthropic).first(where: { $0.id == "claude-sonnet-4-6" })
        )

        XCTAssertEqual(resolved.id, "claude-sonnet-4-6")
        XCTAssertEqual(resolved.name, "Build Agent")
        XCTAssertEqual(resolved.contextWindow, remoteModel.contextWindow)
        XCTAssertEqual(resolved.maxOutputTokens, remoteModel.maxOutputTokens)
        XCTAssertEqual(resolved.capabilities, remoteModel.capabilities)
    }
}
