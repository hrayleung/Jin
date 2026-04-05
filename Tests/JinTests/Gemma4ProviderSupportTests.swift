import XCTest
@testable import Jin

final class Gemma4ProviderSupportTests: XCTestCase {
    func testVercelGemma4CatalogUsesExactIDsAndConservativeCapabilities() {
        for modelID in ["google/gemma-4-31b-it", "google/gemma-4-26b-a4b-it"] {
            let model = ModelCatalog.modelInfo(for: modelID, provider: .vercelAIGateway)
            XCTAssertEqual(model.contextWindow, 262_144, modelID)
            XCTAssertEqual(model.maxOutputTokens, 131_072, modelID)
            XCTAssertTrue(model.capabilities.contains(.streaming), modelID)
            XCTAssertTrue(model.capabilities.contains(.toolCalling), modelID)
            XCTAssertTrue(model.capabilities.contains(.vision), modelID)
            XCTAssertTrue(model.capabilities.contains(.reasoning), modelID)
            XCTAssertFalse(model.capabilities.contains(.audio), modelID)
            XCTAssertFalse(model.capabilities.contains(.promptCaching), modelID)
            XCTAssertFalse(model.capabilities.contains(.nativePDF), modelID)
        }
    }

    func testOpenRouterGemma4CatalogUsesExactIDsAndConservativeCapabilities() {
        let expectedMaxTokens: [String: Int] = [
            "google/gemma-4-31b-it": 131_072,
            "google/gemma-4-26b-a4b-it": 262_144,
        ]

        for modelID in ["google/gemma-4-31b-it", "google/gemma-4-26b-a4b-it"] {
            let model = ModelCatalog.modelInfo(for: modelID, provider: .openrouter)
            XCTAssertEqual(model.contextWindow, 262_144, modelID)
            XCTAssertEqual(model.maxOutputTokens, expectedMaxTokens[modelID], modelID)
            XCTAssertTrue(model.capabilities.contains(.streaming), modelID)
            XCTAssertTrue(model.capabilities.contains(.toolCalling), modelID)
            XCTAssertTrue(model.capabilities.contains(.vision), modelID)
            XCTAssertTrue(model.capabilities.contains(.reasoning), modelID)
            XCTAssertFalse(model.capabilities.contains(.audio), modelID)
            XCTAssertFalse(model.capabilities.contains(.promptCaching), modelID)
            XCTAssertFalse(model.capabilities.contains(.nativePDF), modelID)
        }
    }

    func testGemma4ResolvedSettingsCarryCatalogLimitsForConfirmedProviders() {
        let vercel = ModelCatalog.modelInfo(for: "google/gemma-4-31b-it", provider: .vercelAIGateway)
        let resolvedVercel = ModelSettingsResolver.resolve(model: vercel, providerType: .vercelAIGateway)
        XCTAssertEqual(resolvedVercel.contextWindow, 262_144)
        XCTAssertEqual(resolvedVercel.maxOutputTokens, 131_072)
        XCTAssertEqual(resolvedVercel.reasoningConfig?.type, .effort)
        XCTAssertEqual(resolvedVercel.reasoningConfig?.defaultEffort, .medium)

        let openRouter = ModelCatalog.modelInfo(for: "google/gemma-4-26b-a4b-it", provider: .openrouter)
        let resolvedOpenRouter = ModelSettingsResolver.resolve(model: openRouter, providerType: .openrouter)
        XCTAssertEqual(resolvedOpenRouter.contextWindow, 262_144)
        XCTAssertEqual(resolvedOpenRouter.maxOutputTokens, 262_144)
        XCTAssertEqual(resolvedOpenRouter.reasoningConfig?.type, .effort)
        XCTAssertEqual(resolvedOpenRouter.reasoningConfig?.defaultEffort, .medium)
    }

    func testGemma4ExactMatchSupportIsLimitedToConfirmedProviders() {
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemma-4-31b-it"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemma-4-31b-it"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemma-4-26b-a4b-it"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemma-4-31b-it"))
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemma-4-26b-a4b-it"))

        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .gemini, modelID: "gemma-4-31b-it-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vercelAIGateway, modelID: "google/gemma-4-31b-it-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .openrouter, modelID: "google/gemma-4-31b-it-custom"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .vertexai, modelID: "gemma-4-31b-it"))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .cloudflareAIGateway, modelID: "google-ai-studio/gemma-4-31b-it"))
    }

    func testGemma4OnlyEnablesNativeWebSearchForGeminiTrial() {
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .gemini, modelID: "gemma-4-31b-it"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .vercelAIGateway, modelID: "google/gemma-4-31b-it"))
        XCTAssertFalse(JinModelSupport.supportsNativePDF(providerType: .openrouter, modelID: "google/gemma-4-31b-it"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .gemini, modelID: "gemma-4-31b-it"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "google/gemma-4-31b-it"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "google/gemma-4-31b-it"))
    }
}
