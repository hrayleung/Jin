import XCTest
@testable import Jin

final class CloudflareProviderIntegrationTests: XCTestCase {
    func testCloudflareProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.cloudflareAIGateway.displayName, "Cloudflare AI Gateway")
        XCTAssertEqual(
            ProviderType.cloudflareAIGateway.defaultBaseURL,
            "https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_slug}/compat"
        )
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .cloudflareAIGateway), "Cloudflare")
    }

    func testProviderManagerCreatesOpenAICompatibleAdapterForCloudflareGateway() async throws {
        let config = ProviderConfig(
            id: "cloudflare-ai-gateway",
            name: "Cloudflare AI Gateway",
            type: .cloudflareAIGateway,
            apiKey: "test-token",
            baseURL: ProviderType.cloudflareAIGateway.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is OpenAICompatibleAdapter)
    }

    func testDefaultProviderSeedsIncludeCloudflareGatewayWithoutSeededModels() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let cloudflareProvider = providers.first(where: { $0.type == .cloudflareAIGateway }) else {
            return XCTFail("Expected Cloudflare AI Gateway in default provider seeds.")
        }

        XCTAssertEqual(cloudflareProvider.id, "cloudflare-ai-gateway")
        XCTAssertEqual(cloudflareProvider.baseURL, ProviderType.cloudflareAIGateway.defaultBaseURL)
        XCTAssertTrue(cloudflareProvider.models.isEmpty)
    }
}
