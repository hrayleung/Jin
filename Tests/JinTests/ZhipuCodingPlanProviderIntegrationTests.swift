import XCTest
@testable import Jin

final class ZhipuCodingPlanProviderIntegrationTests: XCTestCase {
    func testZhipuCodingPlanProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.zhipuCodingPlan.displayName, "Zhipu Coding Plan")
        XCTAssertEqual(
            ProviderType.zhipuCodingPlan.defaultBaseURL,
            "https://open.bigmodel.cn/api/coding/paas/v4"
        )
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .zhipuCodingPlan), "Zhipu")
    }

    func testProviderManagerCreatesOpenAICompatibleAdapterForZhipuCodingPlan() async throws {
        let config = ProviderConfig(
            id: "zhipu-coding-plan",
            name: "Zhipu Coding Plan",
            type: .zhipuCodingPlan,
            apiKey: "test-token",
            baseURL: ProviderType.zhipuCodingPlan.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is OpenAICompatibleAdapter)
    }

    func testDefaultProviderSeedsIncludeZhipuCodingPlanWithSeededModels() throws {
        let providers = DefaultProviderSeeds.allProviders()
        guard let provider = providers.first(where: { $0.type == .zhipuCodingPlan }) else {
            return XCTFail("Expected Zhipu Coding Plan in default provider seeds.")
        }

        XCTAssertEqual(provider.id, "zhipu-coding-plan")
        XCTAssertEqual(provider.baseURL, ProviderType.zhipuCodingPlan.defaultBaseURL)
        XCTAssertEqual(provider.models.map(\.id), ["glm-5.3[1m]", "glm-5.3", "glm-5.2[1m]", "glm-5.2", "glm-5", "glm-4.7"])

        let glm53 = try XCTUnwrap(provider.models.first(where: { $0.id == "glm-5.3" }))
        XCTAssertEqual(glm53.contextWindow, 200_000)
        XCTAssertEqual(glm53.maxOutputTokens, 131_072)
        XCTAssertEqual(glm53.reasoningConfig?.defaultEffort, .max)

        let glm53max = try XCTUnwrap(provider.models.first(where: { $0.id == "glm-5.3[1m]" }))
        XCTAssertEqual(glm53max.contextWindow, 1_000_000)
        XCTAssertEqual(glm53max.maxOutputTokens, 131_072)
        XCTAssertEqual(glm53max.reasoningConfig?.defaultEffort, .max)
    }
}
