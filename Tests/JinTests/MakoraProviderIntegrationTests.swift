import XCTest
@testable import Jin

final class MakoraProviderIntegrationTests: XCTestCase {
    func testMakoraProviderTypeDefaultsAndIconMapping() {
        XCTAssertEqual(ProviderType.makora.displayName, "Makora")
        XCTAssertEqual(ProviderType.makora.defaultBaseURL, "https://inference.makora.com/v1")
        XCTAssertEqual(LobeProviderIconCatalog.defaultIconID(for: .makora), "Makora")
        XCTAssertNotNil(LobeProviderIconCatalog.icon(forID: "Makora")?.localPNGImage(useDarkMode: false))
        XCTAssertNotNil(LobeProviderIconCatalog.icon(forID: "Makora")?.localPNGImage(useDarkMode: true))
    }

    func testProviderManagerCreatesMakoraAdapter() async throws {
        let config = ProviderConfig(
            id: "makora",
            name: "Makora",
            type: .makora,
            apiKey: "test-token",
            baseURL: ProviderType.makora.defaultBaseURL,
            models: []
        )

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(for: config)

        XCTAssertTrue(adapter is MakoraAdapter)
    }

    func testDefaultProviderSeedsIncludeMakoraOfficialLineup() {
        let providers = DefaultProviderSeeds.allProviders()
        guard let makora = providers.first(where: { $0.type == .makora }) else {
            return XCTFail("Expected Makora in default provider seeds.")
        }

        XCTAssertEqual(makora.id, "makora")
        XCTAssertEqual(makora.baseURL, ProviderType.makora.defaultBaseURL)
        XCTAssertEqual(
            makora.models.map(\.id),
            [
                "deepseek-ai/DeepSeek-V4-Flash-0731",
                "google/gemma-4-26B-A4B",
                "zai-org/GLM-5.2-FP8",
                "zai-org/GLM-5.2-NVFP4",
                "moonshotai/Kimi-K3",
            ]
        )

        for id in makora.models.map(\.id) {
            XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .makora, modelID: id), id)
        }
    }

    func testMakoraCatalogMetadataForOfficialAndAPIDiscoveredIDs() {
        let kimi = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K3", provider: .makora)
        XCTAssertEqual(kimi.contextWindow, 1_048_576)
        XCTAssertTrue(kimi.capabilities.contains(.vision))
        XCTAssertTrue(kimi.capabilities.contains(.reasoning))
        XCTAssertEqual(kimi.reasoningConfig?.type, .effort)
        XCTAssertEqual(kimi.reasoningConfig?.defaultEffort, .max)
        XCTAssertEqual(kimi.reasoningConfig?.supportedEfforts, [.low, .high, .max])

        let flash = ModelCatalog.modelInfo(for: "deepseek-ai/DeepSeek-V4-Flash-0731", provider: .makora)
        XCTAssertEqual(flash.contextWindow, 1_000_000)
        XCTAssertFalse(flash.capabilities.contains(.vision))
        XCTAssertEqual(flash.reasoningConfig?.supportedEfforts, [.high, .max])

        let gemma = ModelCatalog.modelInfo(for: "google/gemma-4-26B-A4B", provider: .makora)
        XCTAssertEqual(gemma.contextWindow, 131_072)
        XCTAssertFalse(gemma.capabilities.contains(.vision))
        XCTAssertEqual(gemma.reasoningConfig?.type, .toggle)

        let glmFP8 = ModelCatalog.modelInfo(for: "zai-org/GLM-5.2-FP8", provider: .makora)
        XCTAssertEqual(glmFP8.contextWindow, 1_000_000)
        XCTAssertEqual(glmFP8.maxOutputTokens, 16_384)

        let glmNV = ModelCatalog.modelInfo(for: "zai-org/GLM-5.2-NVFP4", provider: .makora)
        XCTAssertEqual(glmNV.contextWindow, 1_000_000)
        XCTAssertNil(glmNV.maxOutputTokens)

        let apiFlash = ModelCatalog.modelInfo(for: "deepseek-ai/DeepSeek-V4-Flash", provider: .makora)
        XCTAssertEqual(apiFlash.contextWindow, 1_048_576)
        XCTAssertEqual(apiFlash.maxOutputTokens, 32_768)
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .makora, modelID: apiFlash.id))

        let llama = ModelCatalog.modelInfo(for: "meta-llama/Llama-3.3-70B-Instruct", provider: .makora)
        XCTAssertFalse(llama.capabilities.contains(.reasoning))
        XCTAssertEqual(llama.maxOutputTokens, 8_192)
    }

    func testUnknownMakoraModelUsesConservativeFallback() {
        let unknown = ModelCatalog.modelInfo(for: "makora/not-a-real-model", provider: .makora)
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertNil(unknown.reasoningConfig)
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .makora, modelID: unknown.id))
    }

    func testGPTOssOnMakoraCannotDisableReasoning() {
        XCTAssertFalse(
            ModelSettingsResolver.defaultReasoningCanDisable(
                for: .makora,
                modelID: "openai/gpt-oss-120b"
            )
        )
        XCTAssertTrue(
            ModelSettingsResolver.defaultReasoningCanDisable(
                for: .makora,
                modelID: "moonshotai/Kimi-K3"
            )
        )
    }

    func testProviderDetailsTextMentionsMakoraEndpoint() {
        let text = ProviderFormSupport.providerDetailsText(for: .makora)
        XCTAssertEqual(text?.contains("inference.makora.com/v1"), true)
        XCTAssertEqual(text?.contains("chat_template_kwargs"), true)
    }
}
