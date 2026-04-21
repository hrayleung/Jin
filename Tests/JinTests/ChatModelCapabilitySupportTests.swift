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

    func testVideoGenerationBadgeTextUsesGenericOnState() {
        let openRouterBadge = ChatModelCapabilitySupport.videoGenerationBadgeText(
            supportsVideoGenerationControl: true,
            providerType: .openrouter,
            controls: GenerationControls(
                openRouterVideoGeneration: OpenRouterVideoGenerationControls(
                    durationSeconds: 4,
                    resolution: .res480p
                )
            ),
            isVideoGenerationConfigured: true
        )
        XCTAssertEqual(openRouterBadge, "On")

        let xaiBadge = ChatModelCapabilitySupport.videoGenerationBadgeText(
            supportsVideoGenerationControl: true,
            providerType: .xai,
            controls: GenerationControls(
                xaiVideoGeneration: XAIVideoGenerationControls(
                    duration: 5,
                    resolution: .res720p
                )
            ),
            isVideoGenerationConfigured: true
        )
        XCTAssertEqual(xaiBadge, "On")

        let googleBadge = ChatModelCapabilitySupport.videoGenerationBadgeText(
            supportsVideoGenerationControl: true,
            providerType: .gemini,
            controls: GenerationControls(
                googleVideoGeneration: GoogleVideoGenerationControls(
                    durationSeconds: 8,
                    resolution: .res720p
                )
            ),
            isVideoGenerationConfigured: true
        )
        XCTAssertEqual(googleBadge, "On")
    }

    func testNormalizedFireworksModelInfoAddsExactKimiK26Metadata() {
        let model = ModelInfo(
            id: "accounts/fireworks/models/kimi-k2p6",
            name: "accounts/fireworks/models/kimi-k2p6",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 8_192,
            reasoningConfig: nil,
            isEnabled: true
        )

        let normalized = ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: .fireworks
        )

        XCTAssertEqual(normalized.name, "Kimi K2.6")
        XCTAssertEqual(normalized.contextWindow, 262_100)
        XCTAssertTrue(normalized.capabilities.contains(.vision))
        XCTAssertTrue(normalized.capabilities.contains(.reasoning))
        XCTAssertEqual(normalized.reasoningConfig?.defaultEffort, .medium)
    }
}
