import XCTest
@testable import Jin

final class VercelAIGatewayProviderIntegrationTests: XCTestCase {
    func testVercelAIGatewayProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.vercelAIGateway.displayName, "Vercel AI Gateway")
        XCTAssertEqual(
            ProviderType.vercelAIGateway.defaultBaseURL,
            "https://ai-gateway.vercel.sh/v1"
        )
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .vercelAIGateway), "Vercel")
    }

    func testProviderManagerCreatesOpenAICompatibleAdapterForVercelAIGateway() async throws {
        let config = ProviderConfig(
            id: "vercel-ai-gateway",
            name: "Vercel AI Gateway",
            type: .vercelAIGateway,
            apiKey: "test-token",
            baseURL: ProviderType.vercelAIGateway.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is OpenAICompatibleAdapter)
    }

    func testDefaultProviderSeedsIncludeVercelAIGatewayWithoutSeededModels() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let provider = providers.first(where: { $0.type == .vercelAIGateway }) else {
            return XCTFail("Expected Vercel AI Gateway in default provider seeds.")
        }

        XCTAssertEqual(provider.id, "vercel-ai-gateway")
        XCTAssertEqual(provider.baseURL, ProviderType.vercelAIGateway.defaultBaseURL)
        XCTAssertTrue(provider.models.isEmpty)
    }
}
