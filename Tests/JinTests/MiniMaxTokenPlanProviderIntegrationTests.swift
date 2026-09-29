import XCTest
@testable import Jin

final class MiniMaxTokenPlanProviderIntegrationTests: XCTestCase {
    func testMiniMaxTokenPlanProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.minimaxCodingPlan.displayName, "MiniMax Token Plan")
        // Token Plan uses MiniMax's unified OpenAI-compatible endpoint, not the Anthropic surface.
        XCTAssertEqual(ProviderType.minimaxCodingPlan.defaultBaseURL, "https://api.minimax.io/v1")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .minimaxCodingPlan), "MiniMax")
    }

    func testMiniMaxTokenPlanUsesOpenAICompatibleRequestShape() {
        XCTAssertEqual(
            ModelCapabilityRegistry.requestShape(for: .minimaxCodingPlan, modelID: "MiniMax-M3"),
            .openAICompatible
        )
    }

    func testProviderManagerCreatesOpenAICompatibleAdapterForMiniMaxTokenPlan() async throws {
        let config = ProviderConfig(
            id: "minimax-coding-plan",
            name: "MiniMax Token Plan",
            type: .minimaxCodingPlan,
            apiKey: "sk-cp-test",
            baseURL: ProviderType.minimaxCodingPlan.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is OpenAICompatibleAdapter)
    }

    func testDefaultProviderSeedsIncludeMiniMaxTokenPlanWithUnifiedEndpointAndM3() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let provider = providers.first(where: { $0.type == .minimaxCodingPlan }) else {
            return XCTFail("Expected MiniMax Token Plan in default provider seeds.")
        }

        XCTAssertEqual(provider.id, "minimax-coding-plan")
        XCTAssertEqual(provider.name, "MiniMax Token Plan")
        XCTAssertEqual(provider.baseURL, "https://api.minimax.io/v1")
        // M3 is the seeded flagship; reasoning is a toggle on the OpenAI-compatible surface.
        XCTAssertEqual(provider.models.first?.id, "MiniMax-M3")
        XCTAssertEqual(provider.models.first?.reasoningConfig?.type, .toggle)

        // M3.1 Flash Preview is Token-Plan-only and seeded behind M3; it always thinks, so its
        // reasoning is an effort band (no toggle) that cannot be switched off.
        let m31 = provider.models.first(where: { $0.id == "MiniMax-M3.1-Flash-Preview" })
        XCTAssertEqual(m31?.reasoningConfig?.type, .effort)
        XCTAssertEqual(m31?.reasoningConfig?.defaultEffort, .max)
        XCTAssertEqual(m31?.reasoningConfig?.supportedEfforts, [.low, .medium, .high, .xhigh, .max])
        XCTAssertTrue(m31?.capabilities.contains(.vision) == true)
        XCTAssertFalse(m31?.capabilities.contains(.videoInput) == true)
    }

    func testLegacyPersistedM31RowResolvesToTheAlwaysThinkingEffortBand() {
        let legacy = ModelInfo(
            id: "MiniMax-M3.1-Flash-Preview",
            name: "MiniMax-M3.1-Flash-Preview",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000
        )

        let resolved = ModelSettingsResolver.resolve(model: legacy, providerType: .minimaxCodingPlan)
        XCTAssertEqual(resolved.contextWindow, 1_000_000)
        XCTAssertEqual(resolved.maxOutputTokens, 524_288)
        XCTAssertTrue(resolved.capabilities.isSuperset(of: [.vision, .reasoning]))
        XCTAssertEqual(resolved.reasoningConfig?.type, .effort)
        XCTAssertEqual(resolved.reasoningConfig?.supportedEfforts, [.low, .medium, .high, .xhigh, .max])
        XCTAssertFalse(resolved.reasoningCanDisable)
        XCTAssertTrue(resolved.supportsOpenAIStyleReasoningEffort)
    }
}
