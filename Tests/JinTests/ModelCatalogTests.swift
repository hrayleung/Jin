import XCTest
@testable import Jin

final class ModelCatalogTests: XCTestCase {
    func testUnknownGeminiAndVertexIDsUseConservativeFallback() {
        let gemini = ModelCatalog.modelInfo(
            for: "gemini-3-pro-preview-custom",
            provider: .gemini,
            name: "Custom Gemini"
        )
        XCTAssertEqual(gemini.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(gemini.contextWindow, 128_000)
        XCTAssertNil(gemini.reasoningConfig)

        let vertex = ModelCatalog.modelInfo(
            for: "gemini-2.5-pro-experimental",
            provider: .vertexai,
            name: "Custom Vertex"
        )
        XCTAssertEqual(vertex.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(vertex.contextWindow, 128_000)
        XCTAssertNil(vertex.reasoningConfig)
    }

    func testCloudflareRequiresExactCompoundIDMatches() {
        let known = ModelCatalog.modelInfo(
            for: "openai/gpt-5.2",
            provider: .cloudflareAIGateway
        )
        XCTAssertTrue(known.capabilities.contains(.vision))
        XCTAssertFalse(known.capabilities.contains(.nativePDF))

        let unknown = ModelCatalog.modelInfo(
            for: "openai/gpt-5.2-custom",
            provider: .cloudflareAIGateway
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testVercelAIGatewayRequiresExactIDMatches() {
        let known = ModelCatalog.modelInfo(
            for: "anthropic/claude-sonnet-4.6",
            provider: .vercelAIGateway
        )
        XCTAssertTrue(known.capabilities.contains(.reasoning))
        XCTAssertTrue(known.capabilities.contains(.vision))

        let unknown = ModelCatalog.modelInfo(
            for: "anthropic/claude-sonnet-4.6-custom",
            provider: .vercelAIGateway
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testVercelAIGatewayCatalogUsesExactProviderPrefixedIDs() {
        let gpt = ModelCatalog.modelInfo(
            for: "openai/gpt-5.3-codex",
            provider: .vercelAIGateway
        )
        XCTAssertEqual(gpt.contextWindow, 400_000)
        XCTAssertTrue(gpt.capabilities.contains(.reasoning))
        XCTAssertTrue(gpt.capabilities.contains(.promptCaching))

        let gemini = ModelCatalog.modelInfo(
            for: "google/gemini-3.1-pro-preview",
            provider: .vercelAIGateway
        )
        XCTAssertEqual(gemini.contextWindow, 1_048_576)
        XCTAssertTrue(gemini.capabilities.contains(.vision))
        XCTAssertTrue(gemini.capabilities.contains(.reasoning))

        let gemma4 = ModelCatalog.modelInfo(
            for: "google/gemma-4-31b-it",
            provider: .vercelAIGateway
        )
        XCTAssertEqual(gemma4.contextWindow, 262_144)
        XCTAssertEqual(gemma4.maxOutputTokens, 131_072)
        XCTAssertTrue(gemma4.capabilities.contains(.toolCalling))
        XCTAssertTrue(gemma4.capabilities.contains(.vision))
        XCTAssertTrue(gemma4.capabilities.contains(.reasoning))
        XCTAssertFalse(gemma4.capabilities.contains(.nativePDF))
    }

    func testOpenRouterGemma4CatalogUsesExactProviderPrefixedIDs() {
        let gemma31 = ModelCatalog.modelInfo(
            for: "google/gemma-4-31b-it",
            provider: .openrouter
        )
        XCTAssertEqual(gemma31.contextWindow, 262_144)
        XCTAssertEqual(gemma31.maxOutputTokens, 131_072)
        XCTAssertTrue(gemma31.capabilities.contains(.toolCalling))
        XCTAssertTrue(gemma31.capabilities.contains(.vision))
        XCTAssertTrue(gemma31.capabilities.contains(.reasoning))

        let gemma26 = ModelCatalog.modelInfo(
            for: "google/gemma-4-26b-a4b-it",
            provider: .openrouter
        )
        XCTAssertEqual(gemma26.contextWindow, 262_144)
        XCTAssertEqual(gemma26.maxOutputTokens, 262_144)
        XCTAssertTrue(gemma26.capabilities.contains(.toolCalling))
        XCTAssertTrue(gemma26.capabilities.contains(.vision))
        XCTAssertTrue(gemma26.capabilities.contains(.reasoning))
    }

    func testGeminiGemma431CatalogUsesExactMetadata() {
        let model = ModelCatalog.modelInfo(
            for: "gemma-4-31b-it",
            provider: .gemini
        )
        XCTAssertEqual(model.contextWindow, 262_144)
        XCTAssertNil(model.maxOutputTokens)
        XCTAssertTrue(model.capabilities.contains(.streaming))
        XCTAssertTrue(model.capabilities.contains(.toolCalling))
        XCTAssertTrue(model.capabilities.contains(.vision))
        XCTAssertTrue(model.capabilities.contains(.reasoning))
        XCTAssertFalse(model.capabilities.contains(.audio))
        XCTAssertFalse(model.capabilities.contains(.nativePDF))
        XCTAssertFalse(model.capabilities.contains(.promptCaching))
        XCTAssertEqual(model.reasoningConfig?.type, .effort)
        XCTAssertEqual(model.reasoningConfig?.defaultEffort, .medium)
    }

    func testOpenAIAudioModelsAreCatalogBackedByExactIDs() {
        let audioPreview = ModelCatalog.modelInfo(
            for: "gpt-4o-audio-preview",
            provider: .openai
        )
        XCTAssertTrue(audioPreview.capabilities.contains(.audio))

        let realtime = ModelCatalog.modelInfo(
            for: "gpt-realtime-mini",
            provider: .openai
        )
        XCTAssertTrue(realtime.capabilities.contains(.audio))
    }

    func testOpenAIGPT53ChatLatestUsesExactCatalogMetadata() {
        let model = ModelCatalog.modelInfo(
            for: "gpt-5.3-chat-latest",
            provider: .openai
        )
        XCTAssertEqual(model.contextWindow, 128_000)
        XCTAssertTrue(model.capabilities.contains(.streaming))
        XCTAssertTrue(model.capabilities.contains(.toolCalling))
        XCTAssertTrue(model.capabilities.contains(.vision))
        XCTAssertTrue(model.capabilities.contains(.promptCaching))
        XCTAssertFalse(model.capabilities.contains(.reasoning))
        XCTAssertFalse(model.capabilities.contains(.nativePDF))
        XCTAssertNil(model.reasoningConfig)

        let cloudflareModel = ModelCatalog.modelInfo(
            for: "openai/gpt-5.3-chat-latest",
            provider: .cloudflareAIGateway
        )
        XCTAssertEqual(cloudflareModel.contextWindow, 128_000)
        XCTAssertTrue(cloudflareModel.capabilities.contains(.vision))
        XCTAssertTrue(cloudflareModel.capabilities.contains(.promptCaching))
        XCTAssertFalse(cloudflareModel.capabilities.contains(.reasoning))
        XCTAssertFalse(cloudflareModel.capabilities.contains(.nativePDF))
        XCTAssertNil(cloudflareModel.reasoningConfig)
    }

    func testOpenAIGPT52AndNewerCatalogDefaultsToNoReasoningEffort() {
        let gpt54 = ModelCatalog.modelInfo(for: "gpt-5.4", provider: .openai)
        XCTAssertEqual(gpt54.reasoningConfig?.type, .effort)
        XCTAssertEqual(gpt54.reasoningConfig?.defaultEffort, ReasoningEffort.none)

        let gpt52 = ModelCatalog.modelInfo(for: "gpt-5.2", provider: .openai)
        XCTAssertEqual(gpt52.reasoningConfig?.defaultEffort, ReasoningEffort.none)

        let gpt54Mini = ModelCatalog.modelInfo(for: "gpt-5.4-mini", provider: .openaiWebSocket)
        XCTAssertEqual(gpt54Mini.reasoningConfig?.defaultEffort, ReasoningEffort.none)

        let cloudflareMini = ModelCatalog.modelInfo(for: "openai/gpt-5.4-mini", provider: .cloudflareAIGateway)
        XCTAssertEqual(cloudflareMini.reasoningConfig?.defaultEffort, ReasoningEffort.none)

        let vercelNano = ModelCatalog.modelInfo(for: "openai/gpt-5.4-nano", provider: .vercelAIGateway)
        XCTAssertEqual(vercelNano.reasoningConfig?.defaultEffort, ReasoningEffort.none)
    }

    func testZhipuCodingPlanExactModelMetadataAndUnknownFallback() {
        let glm5 = ModelCatalog.modelInfo(
            for: "glm-5",
            provider: .zhipuCodingPlan
        )
        XCTAssertEqual(glm5.contextWindow, 200_000)
        XCTAssertTrue(glm5.capabilities.contains(.streaming))
        XCTAssertTrue(glm5.capabilities.contains(.toolCalling))
        XCTAssertTrue(glm5.capabilities.contains(.reasoning))
        XCTAssertTrue(glm5.capabilities.contains(.promptCaching))
        XCTAssertEqual(glm5.reasoningConfig?.type, .toggle)

        let glm47 = ModelCatalog.modelInfo(
            for: "GLM-4.7",
            provider: .zhipuCodingPlan
        )
        XCTAssertEqual(glm47.contextWindow, 200_000)
        XCTAssertEqual(glm47.reasoningConfig?.type, .toggle)

        let unknown = ModelCatalog.modelInfo(
            for: "glm-4.7-custom",
            provider: .zhipuCodingPlan
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testNanoBanana2CatalogMetadataUsesExactIDs() {
        let proImage = ModelCatalog.modelInfo(
            for: "gemini-3-pro-image-preview",
            provider: .gemini
        )
        XCTAssertEqual(proImage.contextWindow, 65_536)
        XCTAssertTrue(proImage.capabilities.contains(.imageGeneration))
        XCTAssertTrue(proImage.capabilities.contains(.reasoning))
        XCTAssertNil(proImage.reasoningConfig)

        let gemini = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-image-preview",
            provider: .gemini
        )
        XCTAssertEqual(gemini.contextWindow, 131_072)
        XCTAssertTrue(gemini.capabilities.contains(.imageGeneration))
        XCTAssertTrue(gemini.capabilities.contains(.nativePDF))
        XCTAssertTrue(gemini.capabilities.contains(.reasoning))
        XCTAssertFalse(gemini.capabilities.contains(.toolCalling))
        XCTAssertEqual(gemini.reasoningConfig?.defaultEffort, .minimal)

        let vertex = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-image-preview",
            provider: .vertexai
        )
        XCTAssertEqual(vertex.contextWindow, 131_072)
        XCTAssertTrue(vertex.capabilities.contains(.imageGeneration))
        XCTAssertTrue(vertex.capabilities.contains(.nativePDF))
        XCTAssertTrue(vertex.capabilities.contains(.reasoning))
        XCTAssertFalse(vertex.capabilities.contains(.toolCalling))
        XCTAssertEqual(vertex.reasoningConfig?.defaultEffort, .minimal)
    }

    func testGemini31FlashLiteCatalogMetadata() {
        let gemini = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-lite-preview",
            provider: .gemini
        )
        XCTAssertEqual(gemini.contextWindow, 1_048_576)
        XCTAssertTrue(gemini.capabilities.contains(.streaming))
        XCTAssertTrue(gemini.capabilities.contains(.toolCalling))
        XCTAssertTrue(gemini.capabilities.contains(.vision))
        XCTAssertTrue(gemini.capabilities.contains(.audio))
        XCTAssertTrue(gemini.capabilities.contains(.reasoning))
        XCTAssertTrue(gemini.capabilities.contains(.promptCaching))
        XCTAssertTrue(gemini.capabilities.contains(.nativePDF))
        XCTAssertFalse(gemini.capabilities.contains(.imageGeneration))
        XCTAssertEqual(gemini.reasoningConfig?.type, .effort)
        XCTAssertEqual(gemini.reasoningConfig?.defaultEffort, .minimal)

        let vertex = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-lite-preview",
            provider: .vertexai
        )
        XCTAssertEqual(vertex.contextWindow, 1_048_576)
        XCTAssertTrue(vertex.capabilities.contains(.streaming))
        XCTAssertTrue(vertex.capabilities.contains(.toolCalling))
        XCTAssertTrue(vertex.capabilities.contains(.vision))
        XCTAssertTrue(vertex.capabilities.contains(.audio))
        XCTAssertTrue(vertex.capabilities.contains(.reasoning))
        XCTAssertTrue(vertex.capabilities.contains(.promptCaching))
        XCTAssertTrue(vertex.capabilities.contains(.nativePDF))
        XCTAssertFalse(vertex.capabilities.contains(.imageGeneration))
        XCTAssertEqual(vertex.reasoningConfig?.type, .effort)
        XCTAssertEqual(vertex.reasoningConfig?.defaultEffort, .minimal)
    }

    func testTogetherCatalogMetadataUsesExactIDs() {
        let kimi = ModelCatalog.modelInfo(
            for: "moonshotai/Kimi-K2.5",
            provider: .together
        )
        XCTAssertEqual(kimi.contextWindow, 262_144)
        XCTAssertTrue(kimi.capabilities.contains(.vision))
        XCTAssertTrue(kimi.capabilities.contains(.reasoning))
        XCTAssertEqual(kimi.reasoningConfig?.type, .toggle)

        let glm5 = ModelCatalog.modelInfo(
            for: "zai-org/GLM-5",
            provider: .together
        )
        XCTAssertEqual(glm5.contextWindow, 202_752)
        XCTAssertEqual(glm5.maxOutputTokens, 128_000)
        XCTAssertTrue(glm5.capabilities.contains(.reasoning))
        XCTAssertEqual(glm5.reasoningConfig?.type, .toggle)

        let deepSeek = ModelCatalog.modelInfo(
            for: "deepseek-ai/DeepSeek-V3.1",
            provider: .together
        )
        XCTAssertEqual(deepSeek.contextWindow, 128_000)
        XCTAssertTrue(deepSeek.capabilities.contains(.reasoning))
        XCTAssertEqual(deepSeek.reasoningConfig?.type, .toggle)

        let qwen35 = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3.5-9B",
            provider: .together
        )
        XCTAssertEqual(qwen35.contextWindow, 262_144)
        XCTAssertTrue(qwen35.capabilities.contains(.vision))
        XCTAssertTrue(qwen35.capabilities.contains(.reasoning))
        XCTAssertEqual(qwen35.reasoningConfig?.type, .toggle)

        let gptOSS = ModelCatalog.modelInfo(
            for: "openai/gpt-oss-20b",
            provider: .together
        )
        XCTAssertEqual(gptOSS.contextWindow, 128_000)
        XCTAssertTrue(gptOSS.capabilities.contains(.reasoning))
        XCTAssertEqual(gptOSS.reasoningConfig?.type, .effort)
        XCTAssertEqual(gptOSS.reasoningConfig?.defaultEffort, .medium)
    }

    func testDeepInfraCatalogMetadataUsesExactIDsAndConservativeFallback() {
        let glm5 = ModelCatalog.modelInfo(
            for: "zai-org/GLM-5",
            provider: .deepinfra
        )
        XCTAssertEqual(glm5.contextWindow, 202_752)
        XCTAssertTrue(glm5.capabilities.contains(.streaming))
        XCTAssertTrue(glm5.capabilities.contains(.toolCalling))
        XCTAssertTrue(glm5.capabilities.contains(.reasoning))
        XCTAssertFalse(glm5.capabilities.contains(.vision))
        XCTAssertNil(glm5.reasoningConfig)

        let kimiInstruct = ModelCatalog.modelInfo(
            for: "moonshotai/Kimi-K2-Instruct-0905",
            provider: .deepinfra
        )
        XCTAssertEqual(kimiInstruct.contextWindow, 131_072)
        XCTAssertTrue(kimiInstruct.capabilities.contains(.toolCalling))
        XCTAssertTrue(kimiInstruct.capabilities.contains(.reasoning))
        XCTAssertFalse(kimiInstruct.capabilities.contains(.vision))
        XCTAssertNil(kimiInstruct.reasoningConfig)

        let kimiVision = ModelCatalog.modelInfo(
            for: "moonshotai/Kimi-K2.5",
            provider: .deepinfra
        )
        XCTAssertEqual(kimiVision.contextWindow, 262_144)
        XCTAssertTrue(kimiVision.capabilities.contains(.toolCalling))
        XCTAssertTrue(kimiVision.capabilities.contains(.reasoning))
        XCTAssertTrue(kimiVision.capabilities.contains(.vision))
        XCTAssertNil(kimiVision.reasoningConfig)

        let deepSeek = ModelCatalog.modelInfo(
            for: "deepseek-ai/DeepSeek-V3.2",
            provider: .deepinfra
        )
        XCTAssertEqual(deepSeek.contextWindow, 163_840)
        XCTAssertTrue(deepSeek.capabilities.contains(.toolCalling))
        XCTAssertTrue(deepSeek.capabilities.contains(.reasoning))
        XCTAssertNil(deepSeek.reasoningConfig)

        let unknown = ModelCatalog.modelInfo(
            for: "zai-org/GLM-5-custom",
            provider: .deepinfra
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testDeepInfraSeededModelsUseCuratedExactIDs() {
        let seeded = Set(ModelCatalog.seededModels(for: .deepinfra).map(\.id))
        XCTAssertEqual(
            seeded,
            [
                "zai-org/GLM-5",
                "moonshotai/Kimi-K2-Instruct-0905",
                "deepseek-ai/DeepSeek-V3.2",
                "MiniMaxAI/MiniMax-M2.5",
                "openai/gpt-oss-120b",
                "zai-org/GLM-4.7",
            ]
        )
        XCTAssertFalse(seeded.contains("moonshotai/Kimi-K2.5"))
    }

    func testUnknownTogetherModelUsesConservativeFallback() {
        let unknown = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3.5-397B-A17B-custom",
            provider: .together
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }
}
