import XCTest
@testable import Jin

final class KimiForCodingProviderIntegrationTests: XCTestCase {
    func testKimiForCodingProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.kimiForCoding.displayName, "Kimi for Coding")
        XCTAssertEqual(
            ProviderType.kimiForCoding.defaultBaseURL,
            "https://api.kimi.com/coding"
        )
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .kimiForCoding), "Kimi")
    }

    func testProviderManagerCreatesAnthropicAdapterForKimiForCoding() async throws {
        let config = ProviderConfig(
            id: "kimi-for-coding",
            name: "Kimi for Coding",
            type: .kimiForCoding,
            apiKey: "test-token",
            baseURL: ProviderType.kimiForCoding.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is AnthropicAdapter)
    }

    func testDefaultProviderSeedsIncludeKimiForCodingWithSeededModels() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let provider = providers.first(where: { $0.type == .kimiForCoding }) else {
            return XCTFail("Expected Kimi for Coding in default provider seeds.")
        }

        XCTAssertEqual(provider.id, "kimi-for-coding")
        XCTAssertEqual(provider.baseURL, ProviderType.kimiForCoding.defaultBaseURL)
        XCTAssertEqual(
            provider.models.map(\.id),
            ["k3[1m]", "k3", "kimi-for-coding", "kimi-for-coding-highspeed"]
        )
    }

    func testKimiForCodingCatalogMetadata() {
        let k3Large = ModelCatalog.modelInfo(for: "k3[1m]", provider: .kimiForCoding)
        XCTAssertEqual(k3Large.contextWindow, 1_048_576)

        let k3 = ModelCatalog.modelInfo(for: "k3", provider: .kimiForCoding)
        XCTAssertEqual(k3.contextWindow, 262_144)
        XCTAssertTrue(k3.capabilities.contains(.reasoning))

        let kimiForCoding = ModelCatalog.modelInfo(for: "kimi-for-coding", provider: .kimiForCoding)
        XCTAssertEqual(kimiForCoding.contextWindow, 262_144)
        XCTAssertEqual(kimiForCoding.maxOutputTokens, 262_144)
        XCTAssertTrue(kimiForCoding.capabilities.contains(.vision))
        XCTAssertTrue(kimiForCoding.capabilities.contains(.reasoning))

        let highspeed = ModelCatalog.modelInfo(for: "kimi-for-coding-highspeed", provider: .kimiForCoding)
        XCTAssertEqual(highspeed.contextWindow, 262_144)
        XCTAssertEqual(highspeed.maxOutputTokens, 262_144)
        XCTAssertTrue(highspeed.capabilities.contains(.reasoning))
    }

    func testKimiForCodingBaseURLNormalizationAppendsV1() async {
        let bare = AnthropicAdapter(
            providerConfig: ProviderConfig(
                id: "kimi-for-coding",
                name: "Kimi for Coding",
                type: .kimiForCoding,
                apiKey: "test-token",
                baseURL: "https://api.kimi.com/coding"
            ),
            apiKey: "test-token"
        )
        let bareBaseURL = await bare.baseURL
        XCTAssertEqual(bareBaseURL, "https://api.kimi.com/coding/v1")

        let trailingSlash = AnthropicAdapter(
            providerConfig: ProviderConfig(
                id: "kimi-for-coding",
                name: "Kimi for Coding",
                type: .kimiForCoding,
                apiKey: "test-token",
                baseURL: "https://api.kimi.com/coding/"
            ),
            apiKey: "test-token"
        )
        let trailingSlashBaseURL = await trailingSlash.baseURL
        XCTAssertEqual(trailingSlashBaseURL, "https://api.kimi.com/coding/v1")

        let alreadyVersioned = AnthropicAdapter(
            providerConfig: ProviderConfig(
                id: "kimi-for-coding",
                name: "Kimi for Coding",
                type: .kimiForCoding,
                apiKey: "test-token",
                baseURL: "https://api.kimi.com/coding/v1"
            ),
            apiKey: "test-token"
        )
        let alreadyVersionedBaseURL = await alreadyVersioned.baseURL
        XCTAssertEqual(alreadyVersionedBaseURL, "https://api.kimi.com/coding/v1")
    }
}
