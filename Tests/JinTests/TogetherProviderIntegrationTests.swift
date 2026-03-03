import XCTest
@testable import Jin

final class TogetherProviderIntegrationTests: XCTestCase {
    func testTogetherProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.together.displayName, "Together AI")
        XCTAssertEqual(ProviderType.together.defaultBaseURL, "https://api.together.xyz/v1")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .together), "Together")
    }

    func testProviderManagerCreatesTogetherAdapter() async throws {
        let config = ProviderConfig(
            id: "together",
            name: "Together AI",
            type: .together,
            apiKey: "test-token",
            baseURL: ProviderType.together.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is TogetherAdapter)
    }

    func testDefaultProviderSeedsIncludeTogetherWithFiveSeededModels() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let togetherProvider = providers.first(where: { $0.type == .together }) else {
            return XCTFail("Expected Together AI in default provider seeds.")
        }

        XCTAssertEqual(togetherProvider.id, "together")
        XCTAssertEqual(togetherProvider.baseURL, ProviderType.together.defaultBaseURL)
        XCTAssertEqual(togetherProvider.models.count, 5)
        XCTAssertEqual(
            togetherProvider.models.map(\.id),
            [
                "Qwen/Qwen3.5-397B-A17B",
                "MiniMaxAI/MiniMax-M2.5",
                "zai-org/GLM-5",
                "Qwen/Qwen3-Coder-Next-FP8",
                "moonshotai/Kimi-K2.5",
            ]
        )
    }
}
