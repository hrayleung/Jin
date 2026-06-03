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
    }
}
