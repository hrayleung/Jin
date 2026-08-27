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

    func testDefaultProviderSeedsIncludeTogetherWithLatestSeededModels() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let togetherProvider = providers.first(where: { $0.type == .together }) else {
            return XCTFail("Expected Together AI in default provider seeds.")
        }

        XCTAssertEqual(togetherProvider.id, "together")
        XCTAssertEqual(togetherProvider.baseURL, ProviderType.together.defaultBaseURL)
        XCTAssertEqual(togetherProvider.models.count, 21)
        XCTAssertEqual(
            togetherProvider.models.map(\.id),
            [
                "moonshotai/Kimi-K3",
                "moonshotai/Kimi-K2.5",
                "thinkingmachines/Inkling",
                "moonshotai/Kimi-K2.7-Code",
                "meta/muse-spark-1.2",
                "zai-org/GLM-5.3",
                "zai-org/GLM-5.3-Flash",
                "zai-org/GLM-5.2",
                "zai-org/GLM-5",
                "deepseek-ai/DeepSeek-V3.1",
                "deepseek-ai/DeepSeek-V4-Pro-0813",
                "deepseek-ai/DeepSeek-V4-Flash-0731",
                "openai/gpt-oss-120b",
                "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B",
                "MiniMaxAI/MiniMax-M3",
                "MiniMaxAI/MiniMax-M2.7",
                "nvidia/Nemotron-3.5-Lightning",
                "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3-235B-A22B-Instruct-2507-tput",
                "Qwen/Qwen3-Coder-Next-FP8",
            ]
        )

        let kimiK3 = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K3", provider: .together)
        XCTAssertEqual(kimiK3.contextWindow, 1_048_576)
        XCTAssertEqual(kimiK3.maxOutputTokens, 131_072)
        XCTAssertTrue(kimiK3.capabilities.contains(.vision))
        XCTAssertEqual(kimiK3.reasoningConfig?.defaultEffort, .max)
    }
}
