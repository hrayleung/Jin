import XCTest
@testable import Jin

final class ChatModelCapabilitySupportTests: XCTestCase {
    func testOpenAIImageGenerationModelIDsUseExactSupportTable() {
        XCTAssertTrue(
            ChatModelCapabilitySupport.isImageGenerationModelID(
                providerType: .openai,
                lowerModelID: "gpt-image-2",
                openAIImageGenerationModelIDs: ChatView.openAIImageGenerationModelIDs,
                xAIImageGenerationModelIDs: ChatView.xAIImageGenerationModelIDs,
                geminiImageGenerationModelIDs: ChatView.geminiImageGenerationModelIDs
            )
        )
        XCTAssertTrue(
            ChatModelCapabilitySupport.isImageGenerationModelID(
                providerType: .openaiWebSocket,
                lowerModelID: "gpt-image-2-2026-04-21",
                openAIImageGenerationModelIDs: ChatView.openAIImageGenerationModelIDs,
                xAIImageGenerationModelIDs: ChatView.xAIImageGenerationModelIDs,
                geminiImageGenerationModelIDs: ChatView.geminiImageGenerationModelIDs
            )
        )
        XCTAssertFalse(
            ChatModelCapabilitySupport.isImageGenerationModelID(
                providerType: .openai,
                lowerModelID: "gpt-image-2-custom",
                openAIImageGenerationModelIDs: ChatView.openAIImageGenerationModelIDs,
                xAIImageGenerationModelIDs: ChatView.xAIImageGenerationModelIDs,
                geminiImageGenerationModelIDs: ChatView.geminiImageGenerationModelIDs
            )
        )
    }

    func testSupportsVideoInputUsesMiMoTokenPlanCatalogFallback() {
        XCTAssertTrue(
            ChatModelCapabilitySupport.supportsVideoInput(
                resolvedModelSettings: nil,
                supportsMediaGenerationControl: false,
                providerType: .mimoTokenPlanOpenAI,
                lowerModelID: "mimo-v2-omni"
            )
        )
        XCTAssertTrue(
            ChatModelCapabilitySupport.supportsVideoInput(
                resolvedModelSettings: nil,
                supportsMediaGenerationControl: false,
                providerType: .mimoTokenPlanOpenAI,
                lowerModelID: "mimo-v2.5"
            )
        )

        XCTAssertFalse(
            ChatModelCapabilitySupport.supportsVideoInput(
                resolvedModelSettings: nil,
                supportsMediaGenerationControl: false,
                providerType: .mimoTokenPlanAnthropic,
                lowerModelID: "mimo-v2-omni"
            )
        )
        XCTAssertFalse(
            ChatModelCapabilitySupport.supportsVideoInput(
                resolvedModelSettings: nil,
                supportsMediaGenerationControl: true,
                providerType: .mimoTokenPlanOpenAI,
                lowerModelID: "mimo-v2-omni"
            )
        )
    }

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

    func testNormalizedFireworksModelInfoAddsExactDeepSeekV4ProMetadata() {
        let model = ModelInfo(
            id: "accounts/fireworks/models/deepseek-v4-pro",
            name: "accounts/fireworks/models/deepseek-v4-pro",
            capabilities: [.streaming, .toolCalling, .vision, .promptCaching],
            contextWindow: 8_192,
            reasoningConfig: nil,
            isEnabled: true
        )

        let normalized = ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: .fireworks
        )

        XCTAssertEqual(normalized.name, "DeepSeek V4 Pro")
        XCTAssertEqual(normalized.contextWindow, 1_048_600)
        XCTAssertEqual(normalized.capabilities, [.streaming, .toolCalling, .reasoning])
        XCTAssertEqual(normalized.reasoningConfig?.type, .effort)
        XCTAssertEqual(normalized.reasoningConfig?.defaultEffort, .high)
    }

    func testNormalizedFireworksModelInfoDoesNotPromoteUndocumentedDeepSeekV4ProID() {
        let model = ModelInfo(
            id: "fireworks/deepseek-v4-pro",
            name: "fireworks/deepseek-v4-pro",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 8_192,
            reasoningConfig: nil,
            isEnabled: true
        )

        let normalized = ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: .fireworks
        )

        XCTAssertEqual(normalized.name, "fireworks/deepseek-v4-pro")
        XCTAssertEqual(normalized.contextWindow, 8_192)
        XCTAssertEqual(normalized.capabilities, [.streaming, .toolCalling])
        XCTAssertNil(normalized.reasoningConfig)
    }

    func testNormalizedFireworksModelInfoAddsCatalogOnlyKimiK2ThinkingMetadataWithoutSupportBadge() {
        let model = ModelInfo(
            id: "accounts/fireworks/models/kimi-k2-thinking",
            name: "accounts/fireworks/models/kimi-k2-thinking",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 8_192,
            reasoningConfig: nil,
            isEnabled: true
        )

        let normalized = ChatModelCapabilitySupport.normalizedSelectedModelInfo(
            model,
            providerType: .fireworks
        )

        XCTAssertEqual(normalized.name, "Kimi K2 Thinking")
        XCTAssertEqual(normalized.contextWindow, 262_100)
        XCTAssertTrue(normalized.capabilities.contains(.toolCalling))
        XCTAssertTrue(normalized.capabilities.contains(.reasoning))
        XCTAssertFalse(normalized.capabilities.contains(.vision))
        XCTAssertNil(normalized.reasoningConfig)
        XCTAssertFalse(
            JinModelSupport.isFullySupported(
                providerType: .fireworks,
                modelID: "accounts/fireworks/models/kimi-k2-thinking"
            )
        )
    }
}
