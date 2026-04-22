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

    func testOpenRouterSeedanceCatalogUsesExactVideoModelIDs() {
        let seedance20 = ModelCatalog.modelInfo(
            for: "bytedance/seedance-2.0",
            provider: .openrouter
        )
        XCTAssertTrue(seedance20.capabilities.contains(.videoGeneration))
        XCTAssertFalse(seedance20.capabilities.contains(.streaming))
        XCTAssertEqual(seedance20.contextWindow, 32_768)
        XCTAssertNil(seedance20.maxOutputTokens)
        XCTAssertNil(seedance20.reasoningConfig)

        let unknown = ModelCatalog.modelInfo(
            for: "bytedance/seedance-2.0-custom",
            provider: .openrouter
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testVerifiedKimiK26CatalogMetadataUsesExactProviderIDs() {
        let opencode = ModelCatalog.modelInfo(
            for: "kimi-k2.6",
            provider: .opencodeGo
        )
        XCTAssertEqual(opencode.contextWindow, 262_144)
        XCTAssertNil(opencode.maxOutputTokens)
        XCTAssertTrue(opencode.capabilities.contains(.vision))
        XCTAssertTrue(opencode.capabilities.contains(.reasoning))
        XCTAssertEqual(opencode.reasoningConfig?.defaultEffort, .medium)

        let openRouter = ModelCatalog.modelInfo(
            for: "moonshotai/kimi-k2.6",
            provider: .openrouter
        )
        XCTAssertEqual(openRouter.contextWindow, 262_144)
        XCTAssertEqual(openRouter.maxOutputTokens, 262_144)
        XCTAssertTrue(openRouter.capabilities.contains(.vision))
        XCTAssertTrue(openRouter.capabilities.contains(.reasoning))
        XCTAssertTrue(openRouter.capabilities.contains(.promptCaching))
        XCTAssertEqual(openRouter.reasoningConfig?.defaultEffort, .medium)

        let fireworks = ModelCatalog.modelInfo(
            for: "fireworks/kimi-k2p6",
            provider: .fireworks
        )
        XCTAssertEqual(fireworks.contextWindow, 262_100)
        XCTAssertNil(fireworks.maxOutputTokens)
        XCTAssertTrue(fireworks.capabilities.contains(.vision))
        XCTAssertTrue(fireworks.capabilities.contains(.reasoning))
        XCTAssertFalse(fireworks.capabilities.contains(.promptCaching))
        XCTAssertEqual(fireworks.reasoningConfig?.defaultEffort, .medium)

        let fireworksAccount = ModelCatalog.modelInfo(
            for: "accounts/fireworks/models/kimi-k2p6",
            provider: .fireworks
        )
        XCTAssertEqual(fireworksAccount.contextWindow, 262_100)
        XCTAssertTrue(fireworksAccount.capabilities.contains(.vision))
        XCTAssertTrue(fireworksAccount.capabilities.contains(.reasoning))

        let vercel = ModelCatalog.modelInfo(
            for: "moonshotai/kimi-k2.6",
            provider: .vercelAIGateway
        )
        XCTAssertEqual(vercel.contextWindow, 262_144)
        XCTAssertEqual(vercel.maxOutputTokens, 262_144)
        XCTAssertTrue(vercel.capabilities.contains(.vision))
        XCTAssertTrue(vercel.capabilities.contains(.reasoning))
        XCTAssertTrue(vercel.capabilities.contains(.promptCaching))

        let cloudflare = ModelCatalog.modelInfo(
            for: "@cf/moonshotai/kimi-k2.6",
            provider: .cloudflareAIGateway
        )
        XCTAssertEqual(cloudflare.contextWindow, 262_144)
        XCTAssertNil(cloudflare.maxOutputTokens)
        XCTAssertTrue(cloudflare.capabilities.contains(.vision))
        XCTAssertTrue(cloudflare.capabilities.contains(.reasoning))
        XCTAssertTrue(cloudflare.capabilities.contains(.promptCaching))
    }

    func testVerifiedKimiK26CatalogRequiresExactIDs() {
        let opencode = ModelCatalog.modelInfo(
            for: "kimi-k2.6-custom",
            provider: .opencodeGo
        )
        XCTAssertEqual(opencode.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(opencode.contextWindow, 128_000)

        let openRouter = ModelCatalog.modelInfo(
            for: "moonshotai/kimi-k2.6-custom",
            provider: .openrouter
        )
        XCTAssertEqual(openRouter.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(openRouter.contextWindow, 128_000)

        let fireworks = ModelCatalog.modelInfo(
            for: "fireworks/kimi-k2p6-custom",
            provider: .fireworks
        )
        XCTAssertEqual(fireworks.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(fireworks.contextWindow, 128_000)

        let vercel = ModelCatalog.modelInfo(
            for: "moonshotai/kimi-k2.6-custom",
            provider: .vercelAIGateway
        )
        XCTAssertEqual(vercel.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(vercel.contextWindow, 128_000)

        let cloudflare = ModelCatalog.modelInfo(
            for: "@cf/moonshotai/kimi-k2.6-custom",
            provider: .cloudflareAIGateway
        )
        XCTAssertEqual(cloudflare.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(cloudflare.contextWindow, 128_000)
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

    func testGeminiGemma426CatalogUsesExactMetadata() {
        let model = ModelCatalog.modelInfo(
            for: "gemma-4-26b-a4b-it",
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

    func testOpenAIImage2CatalogUsesExactIDs() {
        let alias = ModelCatalog.modelInfo(
            for: "gpt-image-2",
            provider: .openai
        )
        XCTAssertEqual(alias.contextWindow, 32_000)
        XCTAssertEqual(alias.capabilities, [.imageGeneration])
        XCTAssertNil(alias.reasoningConfig)

        let snapshot = ModelCatalog.modelInfo(
            for: "gpt-image-2-2026-04-21",
            provider: .openai
        )
        XCTAssertEqual(snapshot.contextWindow, 32_000)
        XCTAssertEqual(snapshot.capabilities, [.imageGeneration])
        XCTAssertNil(snapshot.reasoningConfig)

        let unknown = ModelCatalog.modelInfo(
            for: "gpt-image-2-custom",
            provider: .openai
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)

        let seeded = Set(ModelCatalog.seededModels(for: .openai).map(\.id))
        XCTAssertTrue(seeded.contains("gpt-image-2"))
        XCTAssertFalse(seeded.contains("gpt-image-2-2026-04-21"))
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

        let qwen397 = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3.5-397B-A17B",
            provider: .together
        )
        XCTAssertEqual(qwen397.contextWindow, 262_144)
        XCTAssertTrue(qwen397.capabilities.contains(.toolCalling))
        XCTAssertFalse(qwen397.capabilities.contains(.vision))
        XCTAssertFalse(qwen397.capabilities.contains(.reasoning))
        XCTAssertNil(qwen397.reasoningConfig)

        let qwen235 = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3-235B-A22B-Instruct-2507-tput",
            provider: .together
        )
        XCTAssertEqual(qwen235.contextWindow, 262_144)
        XCTAssertTrue(qwen235.capabilities.contains(.toolCalling))
        XCTAssertFalse(qwen235.capabilities.contains(.reasoning))
        XCTAssertNil(qwen235.reasoningConfig)

        let qwenCoderNext = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3-Coder-Next-FP8",
            provider: .together
        )
        XCTAssertEqual(qwenCoderNext.contextWindow, 262_144)
        XCTAssertTrue(qwenCoderNext.capabilities.contains(.toolCalling))
        XCTAssertFalse(qwenCoderNext.capabilities.contains(.reasoning))
        XCTAssertNil(qwenCoderNext.reasoningConfig)

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

        let qwen397 = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3.5-397B-A17B",
            provider: .deepinfra
        )
        XCTAssertEqual(qwen397.contextWindow, 262_144)
        XCTAssertTrue(qwen397.capabilities.contains(.toolCalling))
        XCTAssertTrue(qwen397.capabilities.contains(.vision))
        XCTAssertFalse(qwen397.capabilities.contains(.reasoning))
        XCTAssertNil(qwen397.reasoningConfig)

        let qwen122 = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3.5-122B-A10B",
            provider: .deepinfra
        )
        XCTAssertEqual(qwen122.contextWindow, 262_144)
        XCTAssertTrue(qwen122.capabilities.contains(.toolCalling))
        XCTAssertTrue(qwen122.capabilities.contains(.vision))
        XCTAssertFalse(qwen122.capabilities.contains(.reasoning))
        XCTAssertNil(qwen122.reasoningConfig)

        let kimiVision = ModelCatalog.modelInfo(
            for: "moonshotai/Kimi-K2.5",
            provider: .deepinfra
        )
        XCTAssertEqual(kimiVision.contextWindow, 262_144)
        XCTAssertTrue(kimiVision.capabilities.contains(.toolCalling))
        XCTAssertTrue(kimiVision.capabilities.contains(.reasoning))
        XCTAssertTrue(kimiVision.capabilities.contains(.vision))
        XCTAssertNil(kimiVision.reasoningConfig)

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
                "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.5-122B-A10B",
                "Qwen/Qwen3.5-35B-A3B",
                "Qwen/Qwen3.5-27B",
                "Qwen/Qwen3.5-9B",
            ]
        )
        XCTAssertFalse(seeded.contains("moonshotai/Kimi-K2-Instruct-0905"))
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

    func testFireworksSeededModelsPreferExactKimiK26Default() {
        let seeded = ModelCatalog.seededModels(for: .fireworks).map(\.id)

        XCTAssertEqual(seeded.first, "fireworks/kimi-k2p6")
        XCTAssertTrue(seeded.contains("fireworks/qwen3p6-plus"))
        XCTAssertTrue(seeded.contains("fireworks/deepseek-v3p2"))
        XCTAssertTrue(seeded.contains("fireworks/kimi-k2-instruct-0905"))
        XCTAssertTrue(seeded.contains("fireworks/glm-5"))
        XCTAssertTrue(seeded.contains("fireworks/minimax-m2p5"))
        XCTAssertFalse(seeded.contains("accounts/fireworks/models/kimi-k2p6"))
    }

    func testFireworksCatalogMetadataUsesExactIDsAndConservativeFallback() {
        let qwen36 = ModelCatalog.modelInfo(
            for: "fireworks/qwen3p6-plus",
            provider: .fireworks
        )
        XCTAssertEqual(qwen36.contextWindow, 128_000)
        XCTAssertTrue(qwen36.capabilities.contains(.toolCalling))
        XCTAssertTrue(qwen36.capabilities.contains(.vision))
        XCTAssertFalse(qwen36.capabilities.contains(.reasoning))
        XCTAssertNil(qwen36.reasoningConfig)

        let deepSeek = ModelCatalog.modelInfo(
            for: "accounts/fireworks/models/deepseek-v3p2",
            provider: .fireworks
        )
        XCTAssertEqual(deepSeek.contextWindow, 163_800)
        XCTAssertTrue(deepSeek.capabilities.contains(.toolCalling))
        XCTAssertFalse(deepSeek.capabilities.contains(.vision))
        XCTAssertFalse(deepSeek.capabilities.contains(.reasoning))
        XCTAssertNil(deepSeek.reasoningConfig)

        let kimiInstruct = ModelCatalog.modelInfo(
            for: "fireworks/kimi-k2-instruct-0905",
            provider: .fireworks
        )
        XCTAssertEqual(kimiInstruct.contextWindow, 262_100)
        XCTAssertTrue(kimiInstruct.capabilities.contains(.toolCalling))
        XCTAssertFalse(kimiInstruct.capabilities.contains(.vision))
        XCTAssertFalse(kimiInstruct.capabilities.contains(.reasoning))
        XCTAssertNil(kimiInstruct.reasoningConfig)

        let qwen235 = ModelCatalog.modelInfo(
            for: "accounts/fireworks/models/qwen3-235b-a22b",
            provider: .fireworks
        )
        XCTAssertEqual(qwen235.contextWindow, 131_100)
        XCTAssertTrue(qwen235.capabilities.contains(.toolCalling))
        XCTAssertFalse(qwen235.capabilities.contains(.reasoning))
        XCTAssertNil(qwen235.reasoningConfig)

        let unknown = ModelCatalog.modelInfo(
            for: "accounts/fireworks/models/qwen3p6-plus-custom",
            provider: .fireworks
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testSambaNovaCatalogMetadataUsesExactIDs() {
        let miniMax = ModelCatalog.modelInfo(
            for: "MiniMax-M2.5",
            provider: .sambanova
        )
        XCTAssertEqual(miniMax.contextWindow, 160_000)
        XCTAssertTrue(miniMax.capabilities.contains(.vision))
        XCTAssertFalse(miniMax.capabilities.contains(.reasoning))

        let deepSeekV32 = ModelCatalog.modelInfo(
            for: "DeepSeek-V3.2",
            provider: .sambanova
        )
        XCTAssertEqual(deepSeekV32.contextWindow, 8_192)
        XCTAssertEqual(deepSeekV32.capabilities, [.streaming])
        XCTAssertNil(deepSeekV32.reasoningConfig)

        let qwen235 = ModelCatalog.modelInfo(
            for: "Qwen3-235B-A22B-Instruct-2507",
            provider: .sambanova
        )
        XCTAssertEqual(qwen235.contextWindow, 64_000)
        XCTAssertTrue(qwen235.capabilities.contains(.toolCalling))
        XCTAssertTrue(qwen235.capabilities.contains(.reasoning))
        XCTAssertEqual(qwen235.reasoningConfig?.type, .toggle)

        let gptOSS = ModelCatalog.modelInfo(
            for: "gpt-oss-120b",
            provider: .sambanova
        )
        XCTAssertEqual(gptOSS.contextWindow, 128_000)
        XCTAssertEqual(gptOSS.reasoningConfig?.type, .effort)
    }

    func testCerebrasCatalogMetadataUsesExactIDsAndConservativeFallback() {
        let qwen235 = ModelCatalog.modelInfo(
            for: "qwen-3-235b-a22b-instruct-2507",
            provider: .cerebras
        )
        XCTAssertEqual(qwen235.contextWindow, 65_000)
        XCTAssertEqual(qwen235.maxOutputTokens, 32_000)
        XCTAssertTrue(qwen235.capabilities.contains(.toolCalling))
        XCTAssertFalse(qwen235.capabilities.contains(.reasoning))
        XCTAssertNil(qwen235.reasoningConfig)

        let glm47 = ModelCatalog.modelInfo(
            for: "zai-glm-4.7",
            provider: .cerebras
        )
        XCTAssertEqual(glm47.contextWindow, 64_000)
        XCTAssertEqual(glm47.maxOutputTokens, 40_000)
        XCTAssertTrue(glm47.capabilities.contains(.reasoning))
        XCTAssertEqual(glm47.reasoningConfig?.type, .toggle)

        let gptOSS = ModelCatalog.modelInfo(
            for: "gpt-oss-120b",
            provider: .cerebras
        )
        XCTAssertEqual(gptOSS.contextWindow, 128_000)
        XCTAssertTrue(gptOSS.capabilities.contains(.reasoning))
        XCTAssertEqual(gptOSS.reasoningConfig?.type, .effort)

        let unknown = ModelCatalog.modelInfo(
            for: "qwen-3-235b-a22b-instruct-2507-custom",
            provider: .cerebras
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }
}
