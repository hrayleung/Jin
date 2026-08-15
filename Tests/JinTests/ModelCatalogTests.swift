import XCTest
@testable import Jin

final class ModelCatalogTests: XCTestCase {
    func testMistralMedium35CatalogUsesExactOfficialID() {
        let model = ModelCatalog.modelInfo(
            for: "mistral-medium-3.5",
            provider: .mistral
        )

        XCTAssertEqual(model.name, "Mistral Medium 3.5")
        XCTAssertEqual(model.contextWindow, 262_144)
        XCTAssertNil(model.maxOutputTokens)
        XCTAssertEqual(model.capabilities, [.streaming, .toolCalling, .vision, .reasoning])
        XCTAssertEqual(model.reasoningConfig?.type, .effort)
        XCTAssertEqual(model.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(JinModelSupport.isFullySupported(providerType: .mistral, modelID: "mistral-medium-3.5"))

        let seeded = ModelCatalog.seededModels(for: .mistral)
        XCTAssertTrue(seeded.contains(where: { $0.id == "mistral-medium-3.5" }))
    }

    func testMistralMedium35SimilarIDsUseConservativeFallback() {
        let custom = ModelCatalog.modelInfo(
            for: "mistral-medium-3.5-custom",
            provider: .mistral
        )

        XCTAssertEqual(custom.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(custom.contextWindow, 128_000)
        XCTAssertNil(custom.maxOutputTokens)
        XCTAssertNil(custom.reasoningConfig)
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .mistral, modelID: "mistral-medium-3.5-custom"))
    }

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

    func testOpenRouterGPT54Image2CatalogUsesExactProviderPrefixedID() {
        let model = ModelCatalog.modelInfo(
            for: "openai/gpt-5.4-image-2",
            provider: .openrouter
        )

        XCTAssertEqual(model.contextWindow, 272_000)
        XCTAssertEqual(model.maxOutputTokens, 128_000)
        XCTAssertTrue(model.capabilities.contains(.streaming))
        XCTAssertTrue(model.capabilities.contains(.vision))
        XCTAssertTrue(model.capabilities.contains(.reasoning))
        XCTAssertTrue(model.capabilities.contains(.promptCaching))
        XCTAssertTrue(model.capabilities.contains(.imageGeneration))
        XCTAssertFalse(model.capabilities.contains(.toolCalling))
        XCTAssertFalse(model.capabilities.contains(.nativePDF))
        XCTAssertEqual(model.reasoningConfig?.type, .effort)
        XCTAssertEqual(model.reasoningConfig?.defaultEffort, ReasoningEffort.none)
    }

    func testOpenRouterDeepSeekV4CatalogUsesExactProviderPrefixedIDs() {
        let flash = ModelCatalog.modelInfo(
            for: "deepseek/deepseek-v4-flash",
            provider: .openrouter
        )
        XCTAssertEqual(flash.name, "DeepSeek V4 Flash")
        XCTAssertEqual(flash.contextWindow, 1_048_576)
        XCTAssertEqual(flash.maxOutputTokens, 384_000)
        XCTAssertEqual(flash.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(flash.reasoningConfig?.type, .effort)
        XCTAssertEqual(flash.reasoningConfig?.defaultEffort, .high)

        let pro = ModelCatalog.modelInfo(
            for: "deepseek/deepseek-v4-pro",
            provider: .openrouter
        )
        XCTAssertEqual(pro.name, "DeepSeek V4 Pro")
        XCTAssertEqual(pro.contextWindow, 1_048_576)
        XCTAssertEqual(pro.maxOutputTokens, 384_000)
        XCTAssertEqual(pro.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(pro.reasoningConfig?.type, .effort)
        XCTAssertEqual(pro.reasoningConfig?.defaultEffort, .high)

        let unknown = ModelCatalog.modelInfo(
            for: "deepseek/deepseek-v4-pro-custom",
            provider: .openrouter
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.maxOutputTokens)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testTogetherDeepSeekV4ProCatalogUsesExactProviderID() {
        let pro = ModelCatalog.modelInfo(
            for: "deepseek-ai/DeepSeek-V4-Pro",
            provider: .together
        )
        XCTAssertEqual(pro.name, "DeepSeek V4 Pro")
        XCTAssertEqual(pro.contextWindow, 524_288)
        XCTAssertNil(pro.maxOutputTokens)
        XCTAssertEqual(pro.capabilities, [.streaming, .toolCalling, .reasoning])
        XCTAssertEqual(pro.reasoningConfig?.type, .effort)
        XCTAssertEqual(pro.reasoningConfig?.defaultEffort, .high)

        let flash = ModelCatalog.modelInfo(
            for: "deepseek-ai/DeepSeek-V4-Flash",
            provider: .together
        )
        XCTAssertEqual(flash.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(flash.contextWindow, 128_000)
        XCTAssertNil(flash.maxOutputTokens)
        XCTAssertNil(flash.reasoningConfig)
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

        let seedance25 = ModelCatalog.modelInfo(
            for: "bytedance/seedance-2.5",
            provider: .openrouter
        )
        XCTAssertEqual(seedance25.name, "Seedance 2.5")
        XCTAssertTrue(seedance25.capabilities.contains(.videoGeneration))
        XCTAssertFalse(seedance25.capabilities.contains(.streaming))
        XCTAssertEqual(seedance25.contextWindow, 32_768)
        XCTAssertNil(seedance25.maxOutputTokens)
        XCTAssertNil(seedance25.reasoningConfig)

        let unknown = ModelCatalog.modelInfo(
            for: "bytedance/seedance-2.0-custom",
            provider: .openrouter
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testOpenRouterSeedance25ModelSupportMatchesVideosModelsAPI() {
        let modelID = "bytedance/seedance-2.5"

        XCTAssertEqual(
            OpenRouterVideoModelSupport.supportedDurations(for: modelID),
            [4, 6, 8, 10, 12, 15, 20, 25, 30]
        )
        XCTAssertEqual(
            OpenRouterVideoModelSupport.supportedResolutions(for: modelID),
            [.res480p, .res720p]
        )
        XCTAssertEqual(
            OpenRouterVideoModelSupport.supportedAspectRatios(for: modelID),
            [
                .ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio21x9,
            ]
        )
        XCTAssertFalse(
            OpenRouterVideoModelSupport.supportedAspectRatios(for: modelID).contains(.ratio9x21)
        )
        XCTAssertTrue(OpenRouterVideoModelSupport.supportsAudio(for: modelID))
        XCTAssertTrue(OpenRouterVideoModelSupport.supportsWatermark(for: modelID))
        XCTAssertEqual(OpenRouterVideoModelSupport.providerPassthroughSlug(for: modelID), "seed")
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

    func testOpenCodeGoMiMoV25CatalogUsesExactProviderIDs() {
        let mimoV25Pro = ModelCatalog.modelInfo(
            for: "mimo-v2.5-pro",
            provider: .opencodeGo
        )
        XCTAssertEqual(mimoV25Pro.contextWindow, 1_048_576)
        XCTAssertEqual(mimoV25Pro.maxOutputTokens, 131_072)
        XCTAssertFalse(mimoV25Pro.capabilities.contains(.vision))
        XCTAssertFalse(mimoV25Pro.capabilities.contains(.audio))
        XCTAssertTrue(mimoV25Pro.capabilities.contains(.toolCalling))
        XCTAssertTrue(mimoV25Pro.capabilities.contains(.reasoning))
        XCTAssertEqual(mimoV25Pro.reasoningConfig?.defaultEffort, .medium)

        let mimoV25 = ModelCatalog.modelInfo(
            for: "mimo-v2.5",
            provider: .opencodeGo
        )
        XCTAssertEqual(mimoV25.contextWindow, 1_048_576)
        XCTAssertEqual(mimoV25.maxOutputTokens, 131_072)
        XCTAssertTrue(mimoV25.capabilities.contains(.vision))
        XCTAssertTrue(mimoV25.capabilities.contains(.audio))
        XCTAssertTrue(mimoV25.capabilities.contains(.toolCalling))
        XCTAssertTrue(mimoV25.capabilities.contains(.reasoning))
        XCTAssertEqual(mimoV25.reasoningConfig?.defaultEffort, .medium)
    }

    func testOpenCodeGoAugust2026ModelsUseVerifiedMetadata() {
        // The three models opencode.ai/docs/go added to the Go plan (page updated 2026-08-02).
        let luna = ModelCatalog.modelInfo(for: "gpt-5.6-luna", provider: .opencodeGo)
        XCTAssertEqual(luna.contextWindow, 1_050_000)
        XCTAssertEqual(luna.maxOutputTokens, 128_000)
        XCTAssertEqual(luna.reasoningConfig?.type, .effort)
        XCTAssertEqual(luna.reasoningConfig?.defaultEffort, .medium)
        XCTAssertTrue(luna.capabilities.contains(.vision))
        XCTAssertTrue(luna.capabilities.contains(.promptCaching))
        // Not claimed: .opencodeGo is in the native-PDF deny arm and the gateway hosts no
        // code-interpreter, so claiming these would light up controls that do nothing.
        XCTAssertFalse(luna.capabilities.contains(.nativePDF))
        XCTAssertFalse(luna.capabilities.contains(.codeExecution))
        XCTAssertFalse(luna.capabilities.contains(.videoInput))

        let grok = ModelCatalog.modelInfo(for: "grok-4.5", provider: .opencodeGo)
        XCTAssertEqual(grok.contextWindow, 500_000)
        // xAI publishes no separate output cap; recording one would default max_tokens to the
        // whole context window.
        XCTAssertNil(grok.maxOutputTokens)
        XCTAssertEqual(grok.reasoningConfig?.type, .effort)
        XCTAssertEqual(grok.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(grok.capabilities.contains(.vision))
        XCTAssertFalse(grok.capabilities.contains(.nativePDF))
        XCTAssertFalse(grok.capabilities.contains(.codeExecution))

        let hy3 = ModelCatalog.modelInfo(for: "hy3", provider: .opencodeGo)
        XCTAssertEqual(hy3.contextWindow, 256_000)
        XCTAssertEqual(hy3.maxOutputTokens, 64_000)
        XCTAssertEqual(hy3.reasoningConfig?.type, .effort)
        XCTAssertEqual(hy3.reasoningConfig?.defaultEffort, .high)
        XCTAssertFalse(hy3.capabilities.contains(.vision))  // text-only input

        // hy3-preview shares Hy3's low/high-only band, so it must not default to `medium`.
        let hy3Preview = ModelCatalog.modelInfo(for: "hy3-preview", provider: .opencodeGo)
        XCTAssertEqual(hy3Preview.reasoningConfig?.defaultEffort, .high)

        // All three are seeded, and glm-5.3 is OpenCode Go's first-launch default.
        let seeded = ModelCatalog.seededModels(for: .opencodeGo)
        XCTAssertEqual(seeded.first?.id, "glm-5.3")
        for id in ["gpt-5.6-luna", "grok-4.5", "hy3"] {
            XCTAssertTrue(seeded.contains(where: { $0.id == id }), "\(id) should be seeded")
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .opencodeGo), id)
        }

        // Near-miss IDs must fall back to the conservative default entry, not prefix-match.
        for id in ["gpt-5.6-luna-pro", "grok-4.5-fast", "hy3-custom"] {
            let unknown = ModelCatalog.modelInfo(for: id, provider: .opencodeGo)
            XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling], id)
            XCTAssertEqual(unknown.contextWindow, 128_000, id)
            XCTAssertNil(unknown.reasoningConfig, id)
        }
    }

    func testOpenCodeGoQwen38MaxUsesVerifiedMetadata() {
        // Alibaba's 2026-08-03 flagship, live on the Go /models list the same day.
        // 1M context / 131,072 output per models.dev `opencode-go`, Alibaba Cloud's launch
        // note and Qwen Cloud's model page — the output cap is the Max line's first move off
        // qwen3.7-max's 65,536, so it must not be mirrored from the predecessor.
        let qwen38 = ModelCatalog.modelInfo(for: "qwen3.8-max", provider: .opencodeGo)
        XCTAssertEqual(qwen38.contextWindow, 1_000_000)
        XCTAssertEqual(qwen38.maxOutputTokens, 131_072)
        XCTAssertNotEqual(qwen38.maxOutputTokens, 65_536, "must not inherit qwen3.7-max's cap")
        XCTAssertTrue(qwen38.capabilities.contains(.toolCalling))
        XCTAssertTrue(qwen38.capabilities.contains(.vision))
        XCTAssertTrue(qwen38.capabilities.contains(.reasoning))

        // Reasoning is the Anthropic thinking-budget shape (it routes through /messages),
        // not an OpenAI effort — a `.effort` config here would serialize the wrong field.
        XCTAssertEqual(qwen38.reasoningConfig?.type, .budget)
        XCTAssertEqual(qwen38.reasoningConfig?.defaultBudget, 10_000)
        XCTAssertNil(qwen38.reasoningConfig?.defaultEffort)

        // models.dev lists video input, but /messages translation swaps .video parts for a
        // text notice — same policy as qwen3.7-plus / qwen3.5-plus. The gateway hosts no
        // PDF/code-execution tooling and .opencodeGo has no context-cache controls.
        XCTAssertFalse(qwen38.capabilities.contains(.videoInput))
        XCTAssertFalse(qwen38.capabilities.contains(.nativePDF))
        XCTAssertFalse(qwen38.capabilities.contains(.codeExecution))
        XCTAssertFalse(qwen38.capabilities.contains(.promptCaching))

        // Its thinking is toggleable (models.dev reasoning_options include a toggle), unlike
        // grok-4.5 on the same provider.
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .opencodeGo, modelID: "qwen3.8-max"))
        XCTAssertFalse(ModelSettingsResolver.defaultReasoningCanDisable(for: .opencodeGo, modelID: "grok-4.5"))

        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "qwen3.8-max", provider: .opencodeGo))
        let seeded = ModelCatalog.seededModels(for: .opencodeGo)
        XCTAssertTrue(seeded.contains(where: { $0.id == "qwen3.8-max" }))
        // Seeded, but not first: glm-5.3 stays OpenCode Go's first-launch default
        // (preferredModelID = models.first).
        XCTAssertEqual(seeded.first?.id, "glm-5.3")

        // Near-miss IDs must fall back to the conservative default entry, not prefix-match.
        for id in ["qwen3.8-max-preview", "qwen3.8-plus"] {
            let unknown = ModelCatalog.modelInfo(for: id, provider: .opencodeGo)
            XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling], id)
            XCTAssertEqual(unknown.contextWindow, 128_000, id)
            XCTAssertNil(unknown.reasoningConfig, id)
        }
    }

    func testOpenCodeGoQwen35PlusDoesNotClaimVideoInput() {
        // qwen3.5-plus routes through the Anthropic /messages endpoint, whose translation
        // replaces a .video part with an "unsupported video input" text notice — claiming
        // .videoInput only made the attachment picker accept videos that were silently
        // swapped for a sentence. Same policy the qwen3.7-plus record documents.
        let model = ModelCatalog.modelInfo(for: "qwen3.5-plus", provider: .opencodeGo)
        XCTAssertFalse(model.capabilities.contains(.videoInput))
        XCTAssertTrue(model.capabilities.contains(.vision))
    }

    func testOpenCodeGoGLM52CatalogUsesExactProviderIDs() {
        let glm52 = ModelCatalog.modelInfo(
            for: "glm-5.2",
            provider: .opencodeGo
        )
        XCTAssertEqual(glm52.contextWindow, 1_000_000)
        XCTAssertEqual(glm52.maxOutputTokens, 131_072)
        XCTAssertFalse(glm52.capabilities.contains(.vision))
        XCTAssertFalse(glm52.capabilities.contains(.audio))
        XCTAssertTrue(glm52.capabilities.contains(.toolCalling))
        XCTAssertTrue(glm52.capabilities.contains(.reasoning))
        XCTAssertEqual(glm52.reasoningConfig?.type, .effort)
        XCTAssertEqual(glm52.reasoningConfig?.defaultEffort, .high)

        // GLM-5.2's reasoning_effort only accepts high/max (Z.AI docs), so the selectable
        // efforts must be restricted — Low/Medium would be invalid values for the model.
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .opencodeGo, modelID: "glm-5.2"),
            [.high, .max]
        )

        // GLM-5.3 is the seeded flagship and therefore OpenCode Go's first-launch default
        // (ChatModelSelectionSupport.preferredModelID returns models.first for .opencodeGo).
        let seeded = ModelCatalog.seededModels(for: .opencodeGo)
        XCTAssertEqual(seeded.first?.id, "glm-5.3")

        let unknown = ModelCatalog.modelInfo(
            for: "glm-5.2-custom",
            provider: .opencodeGo
        )
        XCTAssertNil(unknown.maxOutputTokens)
    }

    func testMiMoTokenPlanCatalogUsesExactProviderIDs() {
        let openAIV25Pro = ModelCatalog.modelInfo(
            for: "mimo-v2.5-pro",
            provider: .mimoTokenPlanOpenAI
        )
        XCTAssertEqual(openAIV25Pro.contextWindow, 1_048_576)
        XCTAssertEqual(openAIV25Pro.maxOutputTokens, 131_072)
        XCTAssertFalse(openAIV25Pro.capabilities.contains(.vision))
        XCTAssertFalse(openAIV25Pro.capabilities.contains(.audio))
        XCTAssertFalse(openAIV25Pro.capabilities.contains(.videoInput))
        XCTAssertTrue(openAIV25Pro.capabilities.contains(.toolCalling))
        XCTAssertTrue(openAIV25Pro.capabilities.contains(.reasoning))
        XCTAssertEqual(openAIV25Pro.reasoningConfig?.type, .toggle)

        let openAIV25 = ModelCatalog.modelInfo(
            for: "mimo-v2.5",
            provider: .mimoTokenPlanOpenAI
        )
        XCTAssertEqual(openAIV25.contextWindow, 1_048_576)
        XCTAssertEqual(openAIV25.maxOutputTokens, 131_072)
        XCTAssertTrue(openAIV25.capabilities.contains(.vision))
        XCTAssertTrue(openAIV25.capabilities.contains(.audio))
        XCTAssertTrue(openAIV25.capabilities.contains(.videoInput))
        XCTAssertTrue(openAIV25.capabilities.contains(.toolCalling))
        XCTAssertTrue(openAIV25.capabilities.contains(.reasoning))
        XCTAssertEqual(openAIV25.reasoningConfig?.type, .toggle)

        let openAIFlash = ModelCatalog.modelInfo(
            for: "mimo-v2-flash",
            provider: .mimoTokenPlanOpenAI
        )
        XCTAssertEqual(openAIFlash.contextWindow, 262_144)
        XCTAssertEqual(openAIFlash.maxOutputTokens, 65_536)
        XCTAssertTrue(openAIFlash.capabilities.contains(.reasoning))

        let anthropicOmni = ModelCatalog.modelInfo(
            for: "mimo-v2-omni",
            provider: .mimoTokenPlanAnthropic
        )
        XCTAssertEqual(anthropicOmni.contextWindow, 262_144)
        XCTAssertEqual(anthropicOmni.maxOutputTokens, 131_072)
        XCTAssertTrue(anthropicOmni.capabilities.contains(.vision))
        XCTAssertFalse(anthropicOmni.capabilities.contains(.audio))
        XCTAssertFalse(anthropicOmni.capabilities.contains(.videoInput))
        XCTAssertTrue(anthropicOmni.capabilities.contains(.toolCalling))
        XCTAssertTrue(anthropicOmni.capabilities.contains(.reasoning))
        XCTAssertEqual(anthropicOmni.reasoningConfig?.type, .toggle)
    }

    func testOpenCodeGoDeepSeekV4CatalogUsesExactProviderIDs() {
        let pro = ModelCatalog.modelInfo(
            for: "deepseek-v4-pro",
            provider: .opencodeGo
        )
        XCTAssertEqual(pro.name, "DeepSeek V4 Pro")
        XCTAssertEqual(pro.contextWindow, 1_000_000)
        XCTAssertEqual(pro.maxOutputTokens, 384_000)
        XCTAssertEqual(pro.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(pro.reasoningConfig?.type, .effort)
        XCTAssertEqual(pro.reasoningConfig?.defaultEffort, .high)
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .opencodeGo, modelID: "deepseek-v4-pro"),
            [.high, .max]
        )

        let flash = ModelCatalog.modelInfo(
            for: "deepseek-v4-flash",
            provider: .opencodeGo
        )
        XCTAssertEqual(flash.name, "DeepSeek V4 Flash")
        XCTAssertEqual(flash.contextWindow, 1_000_000)
        XCTAssertEqual(flash.maxOutputTokens, 384_000)
        XCTAssertEqual(flash.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(flash.reasoningConfig?.type, .effort)
        XCTAssertEqual(flash.reasoningConfig?.defaultEffort, .high)
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .opencodeGo, modelID: "deepseek-v4-flash"),
            [.high, .max]
        )
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

    func testOpenCodeGoMiMoV25CatalogRequiresExactIDs() {
        let mimoV25Pro = ModelCatalog.modelInfo(
            for: "mimo-v2.5-pro-preview",
            provider: .opencodeGo
        )
        XCTAssertEqual(mimoV25Pro.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(mimoV25Pro.contextWindow, 128_000)

        let mimoV25 = ModelCatalog.modelInfo(
            for: "mimo-v2.5-experimental",
            provider: .opencodeGo
        )
        XCTAssertEqual(mimoV25.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(mimoV25.contextWindow, 128_000)
    }

    func testMiMoTokenPlanCatalogRequiresExactIDs() {
        let openAIPreview = ModelCatalog.modelInfo(
            for: "mimo-v2.5-pro-preview",
            provider: .mimoTokenPlanOpenAI
        )
        XCTAssertEqual(openAIPreview.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(openAIPreview.contextWindow, 128_000)
        XCTAssertNil(openAIPreview.maxOutputTokens)

        let anthropicPreview = ModelCatalog.modelInfo(
            for: "mimo-v2.5-experimental",
            provider: .mimoTokenPlanAnthropic
        )
        XCTAssertEqual(anthropicPreview.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(anthropicPreview.contextWindow, 128_000)
        XCTAssertNil(anthropicPreview.maxOutputTokens)
    }

    func testOpenCodeGoDeepSeekV4CatalogRequiresExactIDs() {
        let pro = ModelCatalog.modelInfo(
            for: "deepseek-v4-pro-custom",
            provider: .opencodeGo
        )
        XCTAssertEqual(pro.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(pro.contextWindow, 128_000)
        XCTAssertNil(pro.maxOutputTokens)

        let flash = ModelCatalog.modelInfo(
            for: "deepseek-v4-flash-preview",
            provider: .opencodeGo
        )
        XCTAssertEqual(flash.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(flash.contextWindow, 128_000)
        XCTAssertNil(flash.maxOutputTokens)
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

    func testOpenAIGPT55UsesExactCatalogMetadata() {
        let gpt55 = ModelCatalog.modelInfo(for: "gpt-5.5", provider: .openai)
        XCTAssertEqual(gpt55.contextWindow, 1_050_000)
        XCTAssertEqual(gpt55.maxOutputTokens, 128_000)
        XCTAssertTrue(gpt55.capabilities.contains(.streaming))
        XCTAssertTrue(gpt55.capabilities.contains(.toolCalling))
        XCTAssertTrue(gpt55.capabilities.contains(.vision))
        XCTAssertTrue(gpt55.capabilities.contains(.reasoning))
        XCTAssertTrue(gpt55.capabilities.contains(.promptCaching))
        XCTAssertTrue(gpt55.capabilities.contains(.nativePDF))
        XCTAssertTrue(gpt55.capabilities.contains(.codeExecution))
        XCTAssertEqual(gpt55.reasoningConfig?.defaultEffort, .medium)

        let gpt55Pro = ModelCatalog.modelInfo(for: "gpt-5.5-pro", provider: .openai)
        XCTAssertEqual(gpt55Pro.contextWindow, 1_050_000)
        XCTAssertEqual(gpt55Pro.maxOutputTokens, 128_000)
        XCTAssertFalse(gpt55Pro.capabilities.contains(.streaming))
        XCTAssertTrue(gpt55Pro.capabilities.contains(.toolCalling))
        XCTAssertTrue(gpt55Pro.capabilities.contains(.vision))
        XCTAssertTrue(gpt55Pro.capabilities.contains(.reasoning))
        XCTAssertFalse(gpt55Pro.capabilities.contains(.promptCaching))
        XCTAssertTrue(gpt55Pro.capabilities.contains(.nativePDF))
        XCTAssertTrue(gpt55Pro.capabilities.contains(.codeExecution))
        XCTAssertEqual(gpt55Pro.reasoningConfig?.defaultEffort, .high)
    }

    func testOpenAIWebSocketExcludesKnownNonStreamingGPT55ProFromSupportedSeeds() {
        let pro = ModelCatalog.modelInfo(for: "gpt-5.5-pro", provider: .openaiWebSocket)
        XCTAssertEqual(pro.contextWindow, 1_050_000)
        XCTAssertEqual(pro.maxOutputTokens, 128_000)
        XCTAssertFalse(pro.capabilities.contains(.streaming))
        XCTAssertTrue(pro.capabilities.contains(.reasoning))

        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "gpt-5.5-pro", provider: .openaiWebSocket))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "gpt-5.5-pro-2026-04-23", provider: .openaiWebSocket))

        let seeded = Set(ModelCatalog.seededModels(for: .openaiWebSocket).map(\.id))
        XCTAssertTrue(seeded.contains("gpt-5.5"))
        XCTAssertTrue(seeded.contains("gpt-image-2"))
        XCTAssertFalse(seeded.contains("gpt-5.5-pro"))
        XCTAssertFalse(seeded.contains("gpt-5.5-pro-2026-04-23"))
    }

    func testOpenAIGPT5FamilyCatalogUsesDocsVerifiedReasoningDefaults() {
        let gpt55 = ModelCatalog.modelInfo(for: "gpt-5.5", provider: .openai)
        XCTAssertEqual(gpt55.reasoningConfig?.type, .effort)
        XCTAssertEqual(gpt55.reasoningConfig?.defaultEffort, .medium)

        let gpt55Pro = ModelCatalog.modelInfo(for: "gpt-5.5-pro", provider: .openai)
        XCTAssertEqual(gpt55Pro.reasoningConfig?.type, .effort)
        XCTAssertEqual(gpt55Pro.reasoningConfig?.defaultEffort, .high)

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

    func testZhipuCodingPlanGLM53UsesOfficialTwoIDScheme() {
        // Official Coding Plan docs (docs.z.ai/devpack/latest-model, 2026-08-14) keep the
        // two-ID 200K / 1M scheme. BigModel lists 1M / 128K as the model ceiling.
        let glm53max = ModelCatalog.modelInfo(for: "glm-5.3[1m]", provider: .zhipuCodingPlan)
        XCTAssertEqual(glm53max.name, "GLM-5.3 (1M)")
        XCTAssertEqual(glm53max.contextWindow, 1_000_000)
        XCTAssertEqual(glm53max.maxOutputTokens, 131_072)
        XCTAssertTrue(glm53max.capabilities.contains(.streaming))
        XCTAssertTrue(glm53max.capabilities.contains(.toolCalling))
        XCTAssertTrue(glm53max.capabilities.contains(.reasoning))
        XCTAssertTrue(glm53max.capabilities.contains(.promptCaching))
        XCTAssertFalse(glm53max.capabilities.contains(.vision))
        XCTAssertEqual(glm53max.reasoningConfig?.type, .effort)
        XCTAssertEqual(glm53max.reasoningConfig?.defaultEffort, .max)

        let glm53 = ModelCatalog.modelInfo(for: "glm-5.3", provider: .zhipuCodingPlan)
        XCTAssertEqual(glm53.name, "GLM-5.3")
        XCTAssertEqual(glm53.contextWindow, 200_000)
        XCTAssertEqual(glm53.maxOutputTokens, 131_072)
        XCTAssertEqual(glm53.reasoningConfig?.defaultEffort, .max)

        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .zhipuCodingPlan, modelID: "glm-5.3"),
            [.low, .high, .max]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .zhipuCodingPlan, modelID: "glm-5.3[1m]"),
            [.low, .high, .max]
        )
        XCTAssertFalse(ModelSettingsResolver.defaultReasoningCanDisable(for: .zhipuCodingPlan, modelID: "glm-5.3"))
        XCTAssertFalse(ModelSettingsResolver.defaultReasoningCanDisable(for: .zhipuCodingPlan, modelID: "glm-5.3[1m]"))
        // Older GLM IDs stay toggleable.
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .zhipuCodingPlan, modelID: "glm-5.2"))
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .zhipuCodingPlan, modelID: "glm-5"))

        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "glm-5.3", provider: .zhipuCodingPlan))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "glm-5.3[1m]", provider: .zhipuCodingPlan))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "glm-5.3-custom", provider: .zhipuCodingPlan))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "glm-5.3-preview", provider: .zhipuCodingPlan))

        let seeded = ModelCatalog.seededModels(for: .zhipuCodingPlan)
        XCTAssertEqual(seeded.first?.id, "glm-5.3[1m]")
        XCTAssertTrue(seeded.contains(where: { $0.id == "glm-5.3" }))

        let unknown = ModelCatalog.modelInfo(for: "glm-5.3-custom", provider: .zhipuCodingPlan)
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testOpenCodeGoGLM53CatalogUsesExactProviderIDs() {
        // models.dev `opencode-go` + opencode.ai/docs/go (2026-08-14): glm-5.3,
        // 1M context / 131K output, /chat/completions, low/high/max effort.
        let glm53 = ModelCatalog.modelInfo(for: "glm-5.3", provider: .opencodeGo)
        XCTAssertEqual(glm53.name, "GLM-5.3")
        XCTAssertEqual(glm53.contextWindow, 1_000_000)
        XCTAssertEqual(glm53.maxOutputTokens, 131_072)
        XCTAssertTrue(glm53.capabilities.contains(.streaming))
        XCTAssertTrue(glm53.capabilities.contains(.toolCalling))
        XCTAssertTrue(glm53.capabilities.contains(.reasoning))
        XCTAssertFalse(glm53.capabilities.contains(.vision))
        XCTAssertFalse(glm53.capabilities.contains(.promptCaching))
        XCTAssertEqual(glm53.reasoningConfig?.type, .effort)
        XCTAssertEqual(glm53.reasoningConfig?.defaultEffort, .max)

        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .opencodeGo, modelID: "glm-5.3"),
            [.low, .high, .max]
        )
        // GLM-5.2 keeps its high/max-only band.
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .opencodeGo, modelID: "glm-5.2"),
            [.high, .max]
        )
        XCTAssertFalse(ModelSettingsResolver.defaultReasoningCanDisable(for: .opencodeGo, modelID: "glm-5.3"))

        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "glm-5.3", provider: .opencodeGo))
        XCTAssertEqual(ModelCatalog.seededModels(for: .opencodeGo).first?.id, "glm-5.3")

        let unknown = ModelCatalog.modelInfo(for: "glm-5.3-custom", provider: .opencodeGo)
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "glm-5.3-custom", provider: .opencodeGo))
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
        // Stable GA IDs (seeded)
        let proImage = ModelCatalog.modelInfo(
            for: "gemini-3-pro-image",
            provider: .gemini
        )
        XCTAssertEqual(proImage.contextWindow, 65_536)
        XCTAssertTrue(proImage.capabilities.contains(.imageGeneration))
        XCTAssertTrue(proImage.capabilities.contains(.reasoning))
        XCTAssertNil(proImage.reasoningConfig)

        let gemini = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-image",
            provider: .gemini
        )
        XCTAssertEqual(gemini.contextWindow, 131_072)
        XCTAssertTrue(gemini.capabilities.contains(.imageGeneration))
        XCTAssertTrue(gemini.capabilities.contains(.nativePDF))
        XCTAssertTrue(gemini.capabilities.contains(.reasoning))
        XCTAssertFalse(gemini.capabilities.contains(.toolCalling))
        XCTAssertEqual(gemini.reasoningConfig?.defaultEffort, .minimal)

        let vertex = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-image",
            provider: .vertexai
        )
        XCTAssertEqual(vertex.contextWindow, 131_072)
        XCTAssertTrue(vertex.capabilities.contains(.imageGeneration))
        XCTAssertTrue(vertex.capabilities.contains(.nativePDF))
        XCTAssertTrue(vertex.capabilities.contains(.reasoning))
        XCTAssertFalse(vertex.capabilities.contains(.toolCalling))
        XCTAssertEqual(vertex.reasoningConfig?.defaultEffort, .minimal)

        // Retired preview IDs remain catalog-only for persisted chats.
        XCTAssertNotNil(ModelCatalog.entry(for: "gemini-3.1-flash-image-preview", provider: .gemini))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "gemini-3.1-flash-image-preview", provider: .gemini))
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

    func testGemini31FlashLiteGACatalogMetadata() {
        let gemini = ModelCatalog.modelInfo(
            for: "gemini-3.1-flash-lite",
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
        XCTAssertTrue(gemini.capabilities.contains(.codeExecution))
        XCTAssertFalse(gemini.capabilities.contains(.imageGeneration))
        XCTAssertEqual(gemini.reasoningConfig?.type, .effort)
        XCTAssertEqual(gemini.reasoningConfig?.defaultEffort, .minimal)

        XCTAssertNotNil(ModelCatalog.entry(for: "gemini-3.1-flash-lite", provider: .vertexai))

        let geminiSeeded = Set(ModelCatalog.seededModels(for: .gemini).map(\.id))
        XCTAssertTrue(geminiSeeded.contains("gemini-3.1-flash-lite"))
        XCTAssertFalse(geminiSeeded.contains("gemini-3.1-flash-lite-preview"))
        XCTAssertFalse(geminiSeeded.contains("gemini-3-pro-preview"))
        XCTAssertTrue(geminiSeeded.contains("gemini-3.1-flash-image"))
        XCTAssertTrue(geminiSeeded.contains("gemini-3-pro-image"))
        let vertexSeeded = Set(ModelCatalog.seededModels(for: .vertexai).map(\.id))
        XCTAssertTrue(vertexSeeded.contains("gemini-3.1-flash-lite"))
        XCTAssertFalse(vertexSeeded.contains("gemini-3.1-flash-lite-preview"))
        XCTAssertFalse(vertexSeeded.contains("gemini-3-pro-preview"))
        XCTAssertTrue(vertexSeeded.contains("gemini-3.1-flash-image"))
        XCTAssertTrue(vertexSeeded.contains("gemini-3-pro-image"))
    }

    func testGemini31FlashLiteGAGatewayCatalogMetadata() {
        let openRouter = ModelCatalog.modelInfo(
            for: "google/gemini-3.1-flash-lite",
            provider: .openrouter
        )
        XCTAssertEqual(openRouter.contextWindow, 1_048_576)
        XCTAssertTrue(openRouter.capabilities.contains(.toolCalling))
        XCTAssertTrue(openRouter.capabilities.contains(.audio))
        XCTAssertEqual(openRouter.reasoningConfig?.defaultEffort, .minimal)

        let cloudflareVertex = ModelCatalog.modelInfo(
            for: "google-vertex-ai/google/gemini-3.1-flash-lite-preview",
            provider: .cloudflareAIGateway
        )
        XCTAssertEqual(cloudflareVertex.contextWindow, 1_048_576)
        XCTAssertTrue(cloudflareVertex.capabilities.contains(.toolCalling))
        XCTAssertEqual(cloudflareVertex.reasoningConfig?.defaultEffort, .minimal)
        XCTAssertNil(
            ModelCatalog.entry(
                for: "google-vertex-ai/google/gemini-3.1-flash-lite",
                provider: .cloudflareAIGateway
            )
        )

        let cloudflareAIStudio = ModelCatalog.modelInfo(
            for: "google-ai-studio/gemini-3.1-flash-lite",
            provider: .cloudflareAIGateway
        )
        XCTAssertEqual(cloudflareAIStudio.contextWindow, 1_048_576)
        XCTAssertTrue(cloudflareAIStudio.capabilities.contains(.nativePDF))
        XCTAssertEqual(cloudflareAIStudio.reasoningConfig?.defaultEffort, .minimal)

        let vercel = ModelCatalog.modelInfo(
            for: "google/gemini-3.1-flash-lite",
            provider: .vercelAIGateway
        )
        XCTAssertEqual(vercel.contextWindow, 1_048_576)
        XCTAssertTrue(vercel.capabilities.contains(.toolCalling))
        XCTAssertEqual(vercel.reasoningConfig?.defaultEffort, .minimal)
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
        let glm51 = ModelCatalog.modelInfo(
            for: "zai-org/GLM-5.1",
            provider: .deepinfra
        )
        XCTAssertEqual(glm51.name, "GLM-5.1")
        XCTAssertEqual(glm51.contextWindow, 202_752)
        XCTAssertTrue(glm51.capabilities.contains(.streaming))
        XCTAssertTrue(glm51.capabilities.contains(.toolCalling))
        XCTAssertTrue(glm51.capabilities.contains(.reasoning))
        XCTAssertFalse(glm51.capabilities.contains(.vision))
        XCTAssertNil(glm51.reasoningConfig)

        let qwen36 = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3.6-35B-A3B",
            provider: .deepinfra
        )
        XCTAssertEqual(qwen36.name, "Qwen3.6 35B A3B")
        XCTAssertEqual(qwen36.contextWindow, 262_144)
        XCTAssertTrue(qwen36.capabilities.contains(.toolCalling))
        XCTAssertTrue(qwen36.capabilities.contains(.vision))
        XCTAssertTrue(qwen36.capabilities.contains(.reasoning))
        XCTAssertNil(qwen36.reasoningConfig)

        let nemotronOmni = ModelCatalog.modelInfo(
            for: "nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning",
            provider: .deepinfra
        )
        XCTAssertEqual(nemotronOmni.contextWindow, 262_144)
        XCTAssertTrue(nemotronOmni.capabilities.contains(.toolCalling))
        XCTAssertTrue(nemotronOmni.capabilities.contains(.vision))
        XCTAssertTrue(nemotronOmni.capabilities.contains(.audio))
        XCTAssertTrue(nemotronOmni.capabilities.contains(.videoInput))
        XCTAssertTrue(nemotronOmni.capabilities.contains(.reasoning))
        XCTAssertNil(nemotronOmni.reasoningConfig)

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

        let deepSeekV4Flash = ModelCatalog.modelInfo(
            for: "deepseek-ai/DeepSeek-V4-Flash",
            provider: .deepinfra
        )
        XCTAssertEqual(deepSeekV4Flash.name, "DeepSeek V4 Flash")
        XCTAssertEqual(deepSeekV4Flash.contextWindow, 1_048_576)
        XCTAssertNil(deepSeekV4Flash.maxOutputTokens)
        XCTAssertEqual(deepSeekV4Flash.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(deepSeekV4Flash.reasoningConfig?.type, .effort)
        XCTAssertEqual(deepSeekV4Flash.reasoningConfig?.defaultEffort, .high)

        let deepSeekV4Pro = ModelCatalog.modelInfo(
            for: "deepseek-ai/DeepSeek-V4-Pro",
            provider: .deepinfra
        )
        XCTAssertEqual(deepSeekV4Pro.name, "DeepSeek V4 Pro")
        XCTAssertEqual(deepSeekV4Pro.contextWindow, 65_536)
        XCTAssertNil(deepSeekV4Pro.maxOutputTokens)
        XCTAssertEqual(deepSeekV4Pro.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(deepSeekV4Pro.reasoningConfig?.type, .effort)
        XCTAssertEqual(deepSeekV4Pro.reasoningConfig?.defaultEffort, .high)

        let nemotronSuper = ModelCatalog.modelInfo(
            for: "nvidia/NVIDIA-Nemotron-3-Super-120B-A12B",
            provider: .deepinfra
        )
        XCTAssertEqual(nemotronSuper.contextWindow, 262_144)
        XCTAssertTrue(nemotronSuper.capabilities.contains(.toolCalling))
        XCTAssertTrue(nemotronSuper.capabilities.contains(.reasoning))

        let qwenMax = ModelCatalog.modelInfo(
            for: "Qwen/Qwen3-Max",
            provider: .deepinfra
        )
        XCTAssertEqual(qwenMax.contextWindow, 256_000)
        XCTAssertTrue(qwenMax.capabilities.contains(.toolCalling))
        XCTAssertFalse(qwenMax.capabilities.contains(.reasoning))

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
                "moonshotai/Kimi-K3",
                "zai-org/GLM-5.2",
                "zai-org/GLM-5.1",
                "Qwen/Qwen3.6-35B-A3B",
                "nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning",
                "zai-org/GLM-5",
                "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.5-122B-A10B",
                "Qwen/Qwen3.5-35B-A3B",
                "Qwen/Qwen3.5-27B",
                "Qwen/Qwen3.5-9B",
            ]
        )
        XCTAssertFalse(seeded.contains("moonshotai/Kimi-K2-Instruct-0905"))
        XCTAssertFalse(seeded.contains("deepseek-ai/DeepSeek-V4-Flash"))
        XCTAssertFalse(seeded.contains("deepseek-ai/DeepSeek-V4-Pro"))

        let kimiK3 = ModelCatalog.modelInfo(for: "moonshotai/Kimi-K3", provider: .deepinfra)
        XCTAssertEqual(kimiK3.contextWindow, 1_048_576)
        XCTAssertEqual(kimiK3.maxOutputTokens, 131_072)
        XCTAssertTrue(kimiK3.capabilities.contains(.vision))
        XCTAssertEqual(kimiK3.reasoningConfig?.defaultEffort, .max)
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

    func testXAIGrok43CatalogUsesDocsVerifiedExactMetadata() {
        let grok43 = ModelCatalog.modelInfo(
            for: "grok-4.3",
            provider: .xai
        )

        XCTAssertEqual(grok43.name, "Grok 4.3")
        XCTAssertEqual(grok43.contextWindow, 1_000_000)
        XCTAssertTrue(grok43.capabilities.contains(.streaming))
        XCTAssertTrue(grok43.capabilities.contains(.toolCalling))
        XCTAssertTrue(grok43.capabilities.contains(.vision))
        XCTAssertTrue(grok43.capabilities.contains(.reasoning))
        XCTAssertTrue(grok43.capabilities.contains(.promptCaching))
        XCTAssertTrue(grok43.capabilities.contains(.nativePDF))
        XCTAssertTrue(grok43.capabilities.contains(.codeExecution))
        XCTAssertEqual(grok43.reasoningConfig?.type, .effort)
        XCTAssertEqual(grok43.reasoningConfig?.defaultEffort, ReasoningEffort.none)

        let multiAgent = ModelCatalog.modelInfo(
            for: "grok-4.20-multi-agent",
            provider: .xai
        )

        XCTAssertEqual(multiAgent.name, "Grok 4.20 Multi-Agent")
        XCTAssertEqual(multiAgent.contextWindow, 1_000_000)
        XCTAssertTrue(multiAgent.capabilities.contains(.streaming))
        XCTAssertFalse(multiAgent.capabilities.contains(.toolCalling))
        XCTAssertTrue(multiAgent.capabilities.contains(.vision))
        XCTAssertTrue(multiAgent.capabilities.contains(.reasoning))
        XCTAssertTrue(multiAgent.capabilities.contains(.promptCaching))
        XCTAssertTrue(multiAgent.capabilities.contains(.nativePDF))
        XCTAssertTrue(multiAgent.capabilities.contains(.codeExecution))
        XCTAssertEqual(multiAgent.reasoningConfig?.type, .effort)
        XCTAssertEqual(multiAgent.reasoningConfig?.defaultEffort, .low)

        let multiAgentSnapshot = ModelCatalog.modelInfo(
            for: "grok-4.20-multi-agent-0309",
            provider: .xai
        )

        XCTAssertEqual(multiAgentSnapshot.name, "Grok 4.20 Multi-Agent 0309")
        XCTAssertEqual(multiAgentSnapshot.contextWindow, 1_000_000)
        XCTAssertTrue(multiAgentSnapshot.capabilities.contains(.streaming))
        XCTAssertFalse(multiAgentSnapshot.capabilities.contains(.toolCalling))
        XCTAssertTrue(multiAgentSnapshot.capabilities.contains(.vision))
        XCTAssertTrue(multiAgentSnapshot.capabilities.contains(.reasoning))
        XCTAssertTrue(multiAgentSnapshot.capabilities.contains(.promptCaching))
        XCTAssertTrue(multiAgentSnapshot.capabilities.contains(.nativePDF))
        XCTAssertTrue(multiAgentSnapshot.capabilities.contains(.codeExecution))
        XCTAssertEqual(multiAgentSnapshot.reasoningConfig?.type, .effort)
        XCTAssertEqual(multiAgentSnapshot.reasoningConfig?.defaultEffort, .low)

        let grok420 = ModelCatalog.modelInfo(
            for: "grok-4.20",
            provider: .xai
        )

        XCTAssertEqual(grok420.name, "Grok 4.20")
        XCTAssertEqual(grok420.contextWindow, 1_000_000)
        XCTAssertTrue(grok420.capabilities.contains(.streaming))
        XCTAssertTrue(grok420.capabilities.contains(.toolCalling))
        XCTAssertTrue(grok420.capabilities.contains(.vision))
        XCTAssertTrue(grok420.capabilities.contains(.reasoning))
        XCTAssertTrue(grok420.capabilities.contains(.promptCaching))
        XCTAssertTrue(grok420.capabilities.contains(.nativePDF))
        XCTAssertTrue(grok420.capabilities.contains(.codeExecution))
        XCTAssertNil(grok420.reasoningConfig)

        let build = ModelCatalog.modelInfo(for: "grok-build-0.1", provider: .xai)
        XCTAssertEqual(build.contextWindow, 256_000)
        XCTAssertTrue(build.capabilities.contains(.toolCalling))
        XCTAssertTrue(build.capabilities.contains(.codeExecution))
        XCTAssertTrue(build.capabilities.contains(.reasoning))
        // Build reasoning is always-on and non-configurable — no effort UI/API.
        XCTAssertNil(build.reasoningConfig)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "grok-build-0.1", provider: .xai))

        let video15 = ModelCatalog.modelInfo(for: "grok-imagine-video-1.5", provider: .xai)
        XCTAssertTrue(video15.capabilities.contains(.videoGeneration))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "grok-imagine-video-1.5", provider: .xai))

        let unknown = ModelCatalog.modelInfo(
            for: "grok-4.3-custom",
            provider: .xai
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testOpenRouterXAIGrokCatalogUsesExactProviderPrefixedIDs() {
        let grok43 = ModelCatalog.modelInfo(
            for: "x-ai/grok-4.3",
            provider: .openrouter
        )
        XCTAssertEqual(grok43.name, "xAI: Grok 4.3")
        XCTAssertEqual(grok43.contextWindow, 1_000_000)
        XCTAssertTrue(grok43.capabilities.contains(.streaming))
        XCTAssertTrue(grok43.capabilities.contains(.toolCalling))
        XCTAssertTrue(grok43.capabilities.contains(.vision))
        XCTAssertTrue(grok43.capabilities.contains(.reasoning))
        XCTAssertTrue(grok43.capabilities.contains(.promptCaching))
        XCTAssertFalse(grok43.capabilities.contains(.nativePDF))
        XCTAssertEqual(grok43.reasoningConfig?.defaultEffort, .low)

        let grok420 = ModelCatalog.modelInfo(
            for: "x-ai/grok-4.20",
            provider: .openrouter
        )
        XCTAssertEqual(grok420.name, "xAI: Grok 4.20")
        XCTAssertEqual(grok420.contextWindow, 2_000_000)
        XCTAssertTrue(grok420.capabilities.contains(.toolCalling))
        XCTAssertTrue(grok420.capabilities.contains(.vision))
        XCTAssertTrue(grok420.capabilities.contains(.reasoning))
        XCTAssertTrue(grok420.capabilities.contains(.promptCaching))
        XCTAssertFalse(grok420.capabilities.contains(.nativePDF))
        XCTAssertEqual(grok420.reasoningConfig?.defaultEffort, .medium)

        let multiAgent = ModelCatalog.modelInfo(
            for: "x-ai/grok-4.20-multi-agent",
            provider: .openrouter
        )
        XCTAssertEqual(multiAgent.name, "xAI: Grok 4.20 Multi-Agent")
        XCTAssertEqual(multiAgent.contextWindow, 2_000_000)
        XCTAssertTrue(multiAgent.capabilities.contains(.streaming))
        XCTAssertFalse(multiAgent.capabilities.contains(.toolCalling))
        XCTAssertTrue(multiAgent.capabilities.contains(.vision))
        XCTAssertTrue(multiAgent.capabilities.contains(.reasoning))
        XCTAssertTrue(multiAgent.capabilities.contains(.promptCaching))
        XCTAssertFalse(multiAgent.capabilities.contains(.nativePDF))
        XCTAssertEqual(multiAgent.reasoningConfig?.type, .effort)
        XCTAssertEqual(multiAgent.reasoningConfig?.defaultEffort, .low)

        let unknown = ModelCatalog.modelInfo(
            for: "x-ai/grok-4.20-multi-agent-0309",
            provider: .openrouter
        )
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testFireworksSeededModelsPreferExactKimiK3Default() throws {
        let seeded = ModelCatalog.seededModels(for: .fireworks).map(\.id)

        XCTAssertEqual(seeded.first, "accounts/fireworks/models/kimi-k3")
        XCTAssertTrue(seeded.contains("fireworks/kimi-k2p6"))
        XCTAssertTrue(seeded.contains("fireworks/qwen3p6-plus"))
        XCTAssertTrue(seeded.contains("accounts/fireworks/models/deepseek-v4-pro"))
        XCTAssertTrue(seeded.contains("fireworks/deepseek-v3p2"))
        XCTAssertTrue(seeded.contains("fireworks/kimi-k2-instruct-0905"))
        XCTAssertTrue(seeded.contains("fireworks/glm-5"))
        XCTAssertTrue(seeded.contains("fireworks/minimax-m2p5"))
        XCTAssertFalse(seeded.contains("accounts/fireworks/models/kimi-k2p6"))
        // Short alias and fast router stay catalog-only (not seeded).
        XCTAssertFalse(seeded.contains("fireworks/kimi-k3"))
        XCTAssertFalse(seeded.contains("accounts/fireworks/routers/kimi-k3-fast"))

        let v4ProIndex = try XCTUnwrap(seeded.firstIndex(of: "accounts/fireworks/models/deepseek-v4-pro"))
        let v32Index = try XCTUnwrap(seeded.firstIndex(of: "fireworks/deepseek-v3p2"))
        XCTAssertLessThan(v4ProIndex, v32Index)

        let kimiK3 = ModelCatalog.modelInfo(for: "accounts/fireworks/models/kimi-k3", provider: .fireworks)
        XCTAssertEqual(kimiK3.contextWindow, 1_048_576)
        XCTAssertEqual(kimiK3.maxOutputTokens, 131_072)
        XCTAssertTrue(kimiK3.capabilities.contains(.vision))
        XCTAssertEqual(kimiK3.reasoningConfig?.defaultEffort, .max)
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

        let kimiThinking = ModelCatalog.modelInfo(
            for: "fireworks/kimi-k2-thinking",
            provider: .fireworks
        )
        XCTAssertEqual(kimiThinking.name, "Kimi K2 Thinking")
        XCTAssertEqual(kimiThinking.contextWindow, 262_100)
        XCTAssertTrue(kimiThinking.capabilities.contains(.toolCalling))
        XCTAssertTrue(kimiThinking.capabilities.contains(.reasoning))
        XCTAssertFalse(kimiThinking.capabilities.contains(.vision))
        XCTAssertNil(kimiThinking.reasoningConfig)
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "fireworks/kimi-k2-thinking"))

        let kimiThinkingAccount = ModelCatalog.modelInfo(
            for: "accounts/fireworks/models/kimi-k2-thinking",
            provider: .fireworks
        )
        XCTAssertEqual(kimiThinkingAccount.name, "Kimi K2 Thinking")
        XCTAssertEqual(kimiThinkingAccount.contextWindow, 262_100)
        XCTAssertTrue(kimiThinkingAccount.capabilities.contains(.reasoning))
        XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .fireworks, modelID: "accounts/fireworks/models/kimi-k2-thinking"))

        let deepSeekV4Pro = ModelCatalog.modelInfo(
            for: "accounts/fireworks/models/deepseek-v4-pro",
            provider: .fireworks
        )
        XCTAssertEqual(deepSeekV4Pro.name, "DeepSeek V4 Pro")
        XCTAssertEqual(deepSeekV4Pro.contextWindow, 1_048_600)
        XCTAssertNil(deepSeekV4Pro.maxOutputTokens)
        XCTAssertEqual(deepSeekV4Pro.capabilities, [.streaming, .toolCalling, .reasoning])
        XCTAssertEqual(deepSeekV4Pro.reasoningConfig?.type, .effort)
        XCTAssertEqual(deepSeekV4Pro.reasoningConfig?.defaultEffort, .high)

        let deepSeekV4ProAlias = ModelCatalog.modelInfo(
            for: "deepseek-ai/deepseek-v4-pro",
            provider: .fireworks
        )
        XCTAssertEqual(deepSeekV4ProAlias.contextWindow, 1_048_600)
        XCTAssertEqual(deepSeekV4ProAlias.capabilities, [.streaming, .toolCalling, .reasoning])
        XCTAssertEqual(deepSeekV4ProAlias.reasoningConfig?.defaultEffort, .high)

        let undocumentedV4Pro = ModelCatalog.modelInfo(
            for: "fireworks/deepseek-v4-pro",
            provider: .fireworks
        )
        XCTAssertEqual(undocumentedV4Pro.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(undocumentedV4Pro.contextWindow, 128_000)
        XCTAssertNil(undocumentedV4Pro.reasoningConfig)

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

    func testDeepSeekV4CatalogCarriesDocsVerifiedMetadataAndExactIDs() {
        let flash = ModelCatalog.modelInfo(for: "deepseek-v4-flash", provider: .deepseek)
        XCTAssertEqual(flash.name, "DeepSeek V4 Flash")
        XCTAssertEqual(flash.contextWindow, 1_000_000)
        XCTAssertEqual(flash.maxOutputTokens, 384_000)
        XCTAssertTrue(flash.capabilities.contains(.streaming))
        XCTAssertTrue(flash.capabilities.contains(.toolCalling))
        XCTAssertTrue(flash.capabilities.contains(.reasoning))
        XCTAssertTrue(flash.capabilities.contains(.promptCaching))
        XCTAssertEqual(flash.reasoningConfig?.type, .effort)
        XCTAssertEqual(flash.reasoningConfig?.defaultEffort, .high)

        let pro = ModelCatalog.modelInfo(for: "deepseek-v4-pro", provider: .deepseek)
        XCTAssertEqual(pro.name, "DeepSeek V4 Pro")
        XCTAssertEqual(pro.contextWindow, 1_000_000)
        XCTAssertEqual(pro.maxOutputTokens, 384_000)
        XCTAssertEqual(pro.capabilities, [.streaming, .toolCalling, .reasoning, .promptCaching])
        XCTAssertEqual(pro.reasoningConfig?.type, .effort)
        XCTAssertEqual(pro.reasoningConfig?.defaultEffort, .high)

        let unknown = ModelCatalog.modelInfo(for: "deepseek-v4-pro-custom", provider: .deepseek)
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.maxOutputTokens)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testNewOpenRouterModelsExposeVerifiedCatalogMetadata() {
        struct Case {
            let id: String
            let contextWindow: Int
            let maxOutputTokens: Int?
            let required: ModelCapability
            let hasReasoning: Bool
            let effort: ReasoningEffort?
        }

        // Representative slice of the newly curated OpenRouter records, including `~` family
        // aliases, free variants, a router, and hybrid (reasoning-off-by-default) models.
        let cases: [Case] = [
            Case(id: "qwen/qwen3.7-plus", contextWindow: 1_000_000, maxOutputTokens: 65_536,
                 required: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching], hasReasoning: true, effort: .medium),
            Case(id: "minimax/minimax-m3", contextWindow: 1_048_576, maxOutputTokens: 512_000,
                 required: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching], hasReasoning: true, effort: .high),
            Case(id: "anthropic/claude-opus-4.8", contextWindow: 1_000_000, maxOutputTokens: 128_000,
                 required: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching], hasReasoning: true, effort: .high),
            Case(id: "openai/gpt-5.5", contextWindow: 1_050_000, maxOutputTokens: 128_000,
                 required: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching], hasReasoning: true, effort: .medium),
            Case(id: "openai/gpt-5.4-mini", contextWindow: 400_000, maxOutputTokens: 128_000,
                 required: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching], hasReasoning: true, effort: ReasoningEffort.none),
            Case(id: "openai/gpt-chat-latest", contextWindow: 400_000, maxOutputTokens: 128_000,
                 required: [.streaming, .toolCalling, .vision, .promptCaching], hasReasoning: false, effort: nil),
            Case(id: "~openai/gpt-latest", contextWindow: 1_050_000, maxOutputTokens: 128_000,
                 required: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching], hasReasoning: true, effort: .medium),
            Case(id: "~anthropic/claude-opus-latest", contextWindow: 1_000_000, maxOutputTokens: 128_000,
                 required: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching], hasReasoning: true, effort: .high),
            Case(id: "~google/gemini-pro-latest", contextWindow: 1_048_576, maxOutputTokens: 65_536,
                 required: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching], hasReasoning: true, effort: .high),
            Case(id: "google/gemma-4-31b-it:free", contextWindow: 262_144, maxOutputTokens: 32_768,
                 required: [.streaming, .toolCalling, .vision, .reasoning], hasReasoning: true, effort: ReasoningEffort.none),
            Case(id: "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free", contextWindow: 256_000, maxOutputTokens: 65_536,
                 required: [.streaming, .toolCalling, .vision, .audio, .reasoning], hasReasoning: true, effort: .low),
            Case(id: "openrouter/pareto-code", contextWindow: 2_000_000, maxOutputTokens: nil,
                 required: [.streaming], hasReasoning: false, effort: nil),
            Case(id: "z-ai/glm-5.2", contextWindow: 1_048_576, maxOutputTokens: 262_144,
                 required: [.streaming, .toolCalling, .reasoning, .promptCaching], hasReasoning: true, effort: .high),
            Case(id: "z-ai/glm-5.1", contextWindow: 202_752, maxOutputTokens: 131_072,
                 required: [.streaming, .toolCalling, .reasoning, .promptCaching], hasReasoning: true, effort: .high),
            Case(id: "xiaomi/mimo-v2.5", contextWindow: 1_048_576, maxOutputTokens: 131_072,
                 required: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching], hasReasoning: true, effort: .medium),
        ]

        // The OpenRouter adapter drops video parts, text-fallbacks PDFs, and cannot route
        // provider-native code execution — no curated OpenRouter record may claim these.
        let forbidden: ModelCapability = [.videoInput, .nativePDF, .codeExecution]

        for c in cases {
            let model = ModelCatalog.modelInfo(for: c.id, provider: .openrouter)
            XCTAssertEqual(model.contextWindow, c.contextWindow, c.id)
            XCTAssertEqual(model.maxOutputTokens, c.maxOutputTokens, c.id)
            XCTAssertTrue(model.capabilities.isSuperset(of: c.required), "\(c.id) missing expected capabilities")
            XCTAssertTrue(model.capabilities.isDisjoint(with: forbidden), "\(c.id) must not claim video/PDF/code-exec on OpenRouter")
            if c.hasReasoning {
                XCTAssertEqual(model.reasoningConfig?.type, .effort, c.id)
                XCTAssertEqual(model.reasoningConfig?.defaultEffort, c.effort, c.id)
            } else {
                XCTAssertNil(model.reasoningConfig, c.id)
            }
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: c.id, provider: .openrouter), c.id)
        }

        // Reka Edge name was normalized to the catalog-wide "Vendor: Model" convention and is non-reasoning.
        let reka = ModelCatalog.modelInfo(for: "rekaai/reka-edge", provider: .openrouter)
        XCTAssertEqual(reka.name, "Reka AI: Reka Edge")
        XCTAssertTrue(reka.capabilities.contains(.vision))
        XCTAssertFalse(reka.capabilities.contains(.reasoning))
        XCTAssertNil(reka.reasoningConfig)
    }

    func testNewOpenRouterModelsRequireExactIDs() {
        // Near-miss ids (including `~` aliases) must fall back to conservative defaults.
        for id in ["~openai/gpt-latest-custom", "minimax/minimax-m3-preview", "z-ai/glm-5.2-custom", "z-ai/glm-5.1-custom"] {
            let unknown = ModelCatalog.modelInfo(for: id, provider: .openrouter)
            XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling], id)
            XCTAssertEqual(unknown.contextWindow, 128_000, id)
            XCTAssertNil(unknown.maxOutputTokens, id)
            XCTAssertNil(unknown.reasoningConfig, id)
            XCTAssertFalse(ModelCatalog.isFullySupported(modelID: id, provider: .openrouter), id)
        }
    }

    // MARK: - July 2026 additions (GPT-5.6, Grok 4.5, OpenCode Go, OpenRouter)

    func testOpenAIGPT56FamilyCatalogUsesDocsVerifiedExactMetadata() {
        // GPT-5.6 ships as Sol/Terra/Luna (no mini/nano naming, no dated snapshots yet),
        // all 1,050,000 context / 128,000 output with default medium effort.
        for id in ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"] {
            let model = ModelCatalog.modelInfo(for: id, provider: .openai)
            XCTAssertEqual(model.contextWindow, 1_050_000, id)
            XCTAssertEqual(model.maxOutputTokens, 128_000, id)
            XCTAssertTrue(model.capabilities.contains(.streaming), id)
            XCTAssertTrue(model.capabilities.contains(.toolCalling), id)
            XCTAssertTrue(model.capabilities.contains(.vision), id)
            XCTAssertTrue(model.capabilities.contains(.reasoning), id)
            XCTAssertTrue(model.capabilities.contains(.promptCaching), id)
            XCTAssertTrue(model.capabilities.contains(.nativePDF), id)
            XCTAssertTrue(model.capabilities.contains(.codeExecution), id)
            XCTAssertEqual(model.reasoningConfig?.type, .effort, id)
            XCTAssertEqual(model.reasoningConfig?.defaultEffort, .medium, id)
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .openai), id)

            // Gateway twins mirror the verified limits under compound IDs.
            for gateway in [ProviderType.cloudflareAIGateway, .vercelAIGateway] {
                let gatewayModel = ModelCatalog.modelInfo(for: "openai/\(id)", provider: gateway)
                XCTAssertEqual(gatewayModel.contextWindow, 1_050_000, "openai/\(id) via \(gateway)")
                XCTAssertEqual(gatewayModel.maxOutputTokens, 128_000, "openai/\(id) via \(gateway)")
                XCTAssertEqual(gatewayModel.reasoningConfig?.defaultEffort, .medium, "openai/\(id) via \(gateway)")
                XCTAssertFalse(gatewayModel.capabilities.contains(.nativePDF), "openai/\(id) via \(gateway)")
            }
        }

        // No dated snapshots are published for 5.6 — a guessed dated twin must miss.
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "gpt-5.6-sol-2026-07-09", provider: .openai))
        // Official `gpt-5.6` alias routes to Sol and is catalog-recognized.
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "gpt-5.6", provider: .openai))
    }

    func testXAIGrok46CatalogUsesDocsVerifiedExactMetadata() {
        let grok46 = ModelCatalog.modelInfo(for: "grok-4.6", provider: .xai)

        XCTAssertEqual(grok46.name, "Grok 4.6")
        // 500K matches grok-4.5; official release notes publish no text output limit.
        XCTAssertEqual(grok46.contextWindow, 500_000)
        XCTAssertNil(grok46.maxOutputTokens)
        XCTAssertTrue(grok46.capabilities.contains(.streaming))
        XCTAssertTrue(grok46.capabilities.contains(.toolCalling))
        XCTAssertTrue(grok46.capabilities.contains(.vision))
        XCTAssertTrue(grok46.capabilities.contains(.reasoning))
        XCTAssertTrue(grok46.capabilities.contains(.promptCaching))
        XCTAssertTrue(grok46.capabilities.contains(.nativePDF))
        XCTAssertTrue(grok46.capabilities.contains(.codeExecution))
        XCTAssertEqual(grok46.reasoningConfig?.type, .effort)
        XCTAssertEqual(grok46.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "grok-4.6", provider: .xai))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "grok-4.6-custom", provider: .xai))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "grok-4.6", provider: .opencodeGo))

        let vercelGrok46 = ModelCatalog.modelInfo(for: "xai/grok-4.6", provider: .vercelAIGateway)
        XCTAssertEqual(vercelGrok46.contextWindow, 500_000)
        XCTAssertNil(vercelGrok46.maxOutputTokens)
        XCTAssertEqual(vercelGrok46.reasoningConfig?.defaultEffort, .high)

        let openRouterGrok46 = ModelCatalog.modelInfo(for: "x-ai/grok-4.6", provider: .openrouter)
        XCTAssertEqual(openRouterGrok46.contextWindow, 500_000)
        XCTAssertNil(openRouterGrok46.maxOutputTokens)
        XCTAssertEqual(openRouterGrok46.reasoningConfig?.defaultEffort, .high)
        XCTAssertFalse(openRouterGrok46.capabilities.contains(.nativePDF))

        XCTAssertEqual(ModelCatalog.seededModels(for: .xai).first?.id, "grok-4.6")
    }

    func testXAIGrok45CatalogUsesDocsVerifiedExactMetadata() {
        let grok45 = ModelCatalog.modelInfo(for: "grok-4.5", provider: .xai)

        XCTAssertEqual(grok45.name, "Grok 4.5")
        // 500K is a documented REGRESSION vs grok-4.3's 1M — never mirror siblings.
        XCTAssertEqual(grok45.contextWindow, 500_000)
        // xAI publishes no max output for grok-4.5; the catalog must not invent one.
        XCTAssertNil(grok45.maxOutputTokens)
        XCTAssertTrue(grok45.capabilities.contains(.streaming))
        XCTAssertTrue(grok45.capabilities.contains(.toolCalling))
        XCTAssertTrue(grok45.capabilities.contains(.vision))
        XCTAssertTrue(grok45.capabilities.contains(.reasoning))
        XCTAssertTrue(grok45.capabilities.contains(.promptCaching))
        XCTAssertTrue(grok45.capabilities.contains(.nativePDF))
        // code_interpreter is documented for grok-4.5 in the tools overview examples.
        XCTAssertTrue(grok45.capabilities.contains(.codeExecution))
        XCTAssertEqual(grok45.reasoningConfig?.type, .effort)
        XCTAssertEqual(grok45.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "grok-4.5", provider: .xai))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "grok-4.5-custom", provider: .xai))

        // Vercel AI Gateway hosts it as xai/grok-4.5 with the same verified limits.
        let vercelGrok45 = ModelCatalog.modelInfo(for: "xai/grok-4.5", provider: .vercelAIGateway)
        XCTAssertEqual(vercelGrok45.contextWindow, 500_000)
        XCTAssertNil(vercelGrok45.maxOutputTokens)
        XCTAssertEqual(vercelGrok45.reasoningConfig?.defaultEffort, .high)
    }

    func testOpenCodeGoJune2026ModelsUseRegistryVerifiedMetadata() {
        // Seed order stays load-bearing: GLM-5.3 remains the first-launch default.
        XCTAssertEqual(ModelCatalog.seededModels(for: .opencodeGo).first?.id, "glm-5.3")

        let kimiK27Code = ModelCatalog.modelInfo(for: "kimi-k2.7-code", provider: .opencodeGo)
        XCTAssertEqual(kimiK27Code.name, "Kimi K2.7 Code")
        XCTAssertEqual(kimiK27Code.contextWindow, 262_144)
        XCTAssertEqual(kimiK27Code.maxOutputTokens, 262_144)
        XCTAssertTrue(kimiK27Code.capabilities.contains(.toolCalling))
        XCTAssertTrue(kimiK27Code.capabilities.contains(.vision))
        XCTAssertTrue(kimiK27Code.capabilities.contains(.reasoning))
        // Reasoning is always-on with no effort control on the gateway (empty
        // reasoning_options) — no config means Jin never sends an unhonored effort.
        XCTAssertNil(kimiK27Code.reasoningConfig)
        XCTAssertFalse(kimiK27Code.capabilities.contains(.videoInput))

        let qwen37Plus = ModelCatalog.modelInfo(for: "qwen3.7-plus", provider: .opencodeGo)
        XCTAssertEqual(qwen37Plus.name, "Qwen3.7 Plus")
        XCTAssertEqual(qwen37Plus.contextWindow, 1_000_000)
        XCTAssertEqual(qwen37Plus.maxOutputTokens, 65_536)
        XCTAssertTrue(qwen37Plus.capabilities.contains(.vision))
        // The Anthropic /messages route has no video part builder, so despite the
        // registry listing video input the capability is deliberately not claimed.
        XCTAssertFalse(qwen37Plus.capabilities.contains(.videoInput))
        XCTAssertEqual(qwen37Plus.reasoningConfig?.type, .budget)
        XCTAssertEqual(qwen37Plus.reasoningConfig?.defaultBudget, 10_000)
    }

    func testInklingAndKimiK3GatewayCatalogMetadataUsesExactProviderIDs() {
        // Together AI serves Inkling at 524,288 context on its deployment (1M is
        // model-level); max output is unpublished and stays nil (verified via
        // Together's serverless model docs, 2026-07-18).
        let togetherInkling = ModelCatalog.modelInfo(for: "thinkingmachines/Inkling", provider: .together)
        XCTAssertEqual(togetherInkling.name, "Inkling")
        XCTAssertEqual(togetherInkling.contextWindow, 524_288)
        XCTAssertNil(togetherInkling.maxOutputTokens)
        XCTAssertTrue(togetherInkling.capabilities.contains(.streaming))
        XCTAssertTrue(togetherInkling.capabilities.contains(.toolCalling))
        XCTAssertTrue(togetherInkling.capabilities.contains(.vision))
        XCTAssertTrue(togetherInkling.capabilities.contains(.audio))
        XCTAssertTrue(togetherInkling.capabilities.contains(.reasoning))
        XCTAssertTrue(togetherInkling.capabilities.contains(.promptCaching))
        XCTAssertEqual(togetherInkling.reasoningConfig?.type, .effort)
        XCTAssertEqual(togetherInkling.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "thinkingmachines/Inkling", provider: .together))
        XCTAssertTrue(ModelCatalog.seededModels(for: .together).contains(where: { $0.id == "thinkingmachines/Inkling" }))

        // Vercel AI Gateway lists both models (verified via ai-gateway.vercel.sh
        // /v1/models, 2026-07-18): kimi-k3 at 1,000,000 context with always-on
        // max-only thinking, Inkling at 256,000 context/output with no audio tag.
        let vercelKimiK3 = ModelCatalog.modelInfo(for: "moonshotai/kimi-k3", provider: .vercelAIGateway)
        XCTAssertEqual(vercelKimiK3.name, "Kimi K3")
        XCTAssertEqual(vercelKimiK3.contextWindow, 1_000_000)
        XCTAssertEqual(vercelKimiK3.maxOutputTokens, 131_072)
        XCTAssertTrue(vercelKimiK3.capabilities.contains(.vision))
        XCTAssertTrue(vercelKimiK3.capabilities.contains(.reasoning))
        XCTAssertTrue(vercelKimiK3.capabilities.contains(.promptCaching))
        XCTAssertNil(vercelKimiK3.reasoningConfig)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "moonshotai/kimi-k3", provider: .vercelAIGateway))

        let vercelInkling = ModelCatalog.modelInfo(for: "thinkingmachines/inkling", provider: .vercelAIGateway)
        XCTAssertEqual(vercelInkling.name, "Inkling")
        XCTAssertEqual(vercelInkling.contextWindow, 256_000)
        XCTAssertEqual(vercelInkling.maxOutputTokens, 256_000)
        XCTAssertTrue(vercelInkling.capabilities.contains(.vision))
        XCTAssertFalse(vercelInkling.capabilities.contains(.audio))
        XCTAssertTrue(vercelInkling.capabilities.contains(.promptCaching))
        XCTAssertEqual(vercelInkling.reasoningConfig?.type, .effort)
        XCTAssertEqual(vercelInkling.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "thinkingmachines/inkling", provider: .vercelAIGateway))

        // Near-miss IDs fall back to conservative defaults.
        for (provider, id) in [(ProviderType.together, "thinkingmachines/Inkling-Small"), (.vercelAIGateway, "thinkingmachines/inkling-small")] {
            let unknown = ModelCatalog.modelInfo(for: id, provider: provider)
            XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling], id)
            XCTAssertEqual(unknown.contextWindow, 128_000, id)
            XCTAssertNil(unknown.reasoningConfig, id)
        }
    }

    func testOpenCodeGoKimiK3CatalogUsesExactProviderIDs() {
        // Verified against models.dev `opencode-go` and Moonshot's K3 docs (2026-07-18).
        let kimiK3 = ModelCatalog.modelInfo(for: "kimi-k3", provider: .opencodeGo)
        XCTAssertEqual(kimiK3.name, "Kimi K3")
        XCTAssertEqual(kimiK3.contextWindow, 1_048_576)
        XCTAssertEqual(kimiK3.maxOutputTokens, 131_072)
        XCTAssertTrue(kimiK3.capabilities.contains(.streaming))
        XCTAssertTrue(kimiK3.capabilities.contains(.toolCalling))
        XCTAssertTrue(kimiK3.capabilities.contains(.vision))
        XCTAssertTrue(kimiK3.capabilities.contains(.reasoning))
        // Thinking is always-on and effort accepts only "max" — no config means Jin
        // sends no reasoning shape and the endpoint applies max by default.
        XCTAssertNil(kimiK3.reasoningConfig)
        // Video input is listed by models.dev but the OpenAI-compatible route has no
        // video part builder, so the capability is deliberately not claimed.
        XCTAssertFalse(kimiK3.capabilities.contains(.videoInput))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "kimi-k3", provider: .opencodeGo))
        XCTAssertTrue(ModelCatalog.seededModels(for: .opencodeGo).contains(where: { $0.id == "kimi-k3" }))

        // Near-miss IDs must fall back to conservative defaults.
        let unknown = ModelCatalog.modelInfo(for: "kimi-k3-custom", provider: .opencodeGo)
        XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling])
        XCTAssertEqual(unknown.contextWindow, 128_000)
        XCTAssertNil(unknown.reasoningConfig)
    }

    func testNewOpenRouterJuly2026ModelsExposeVerifiedCatalogMetadata() {
        struct Expected {
            let id: String
            let contextWindow: Int
            let maxOutputTokens: Int?
            let reasoningType: ReasoningConfigType?
            let effort: ReasoningEffort?
        }

        let cases: [Expected] = [
            Expected(id: "openai/gpt-5.6-sol", contextWindow: 1_050_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .medium),
            Expected(id: "openai/gpt-5.6-sol-pro", contextWindow: 1_050_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .medium),
            Expected(id: "openai/gpt-5.6-terra", contextWindow: 1_050_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .medium),
            Expected(id: "openai/gpt-5.6-terra-pro", contextWindow: 1_050_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .medium),
            Expected(id: "openai/gpt-5.6-luna", contextWindow: 1_050_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .medium),
            Expected(id: "openai/gpt-5.6-luna-pro", contextWindow: 1_050_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .medium),
            Expected(id: "x-ai/grok-4.6", contextWindow: 500_000, maxOutputTokens: nil, reasoningType: .effort, effort: .high),
            Expected(id: "x-ai/grok-4.5", contextWindow: 500_000, maxOutputTokens: nil, reasoningType: .effort, effort: .high),
            Expected(id: "anthropic/claude-sonnet-5", contextWindow: 1_000_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .medium),
            Expected(id: "anthropic/claude-fable-5", contextWindow: 1_000_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .medium),
            Expected(id: "tencent/hy3", contextWindow: 262_144, maxOutputTokens: nil, reasoningType: .effort, effort: ReasoningEffort.none),
            Expected(id: "tencent/hy3:free", contextWindow: 262_144, maxOutputTokens: 262_144, reasoningType: .effort, effort: ReasoningEffort.none),
            Expected(id: "poolside/laguna-xs-2.1", contextWindow: 262_144, maxOutputTokens: 32_768, reasoningType: .toggle, effort: nil),
            Expected(id: "poolside/laguna-xs-2.1:free", contextWindow: 262_144, maxOutputTokens: 32_768, reasoningType: .toggle, effort: nil),
            Expected(id: "aion-labs/aion-3.0", contextWindow: 131_072, maxOutputTokens: 32_768, reasoningType: nil, effort: nil),
            Expected(id: "google/gemini-3.1-flash-lite-image", contextWindow: 65_536, maxOutputTokens: 66_000, reasoningType: .effort, effort: .minimal),
            Expected(id: "sakana/fugu-ultra", contextWindow: 1_000_000, maxOutputTokens: 128_000, reasoningType: .effort, effort: .xhigh),
            Expected(id: "nex-agi/nex-n2-mini", contextWindow: 262_144, maxOutputTokens: 262_144, reasoningType: .toggle, effort: nil),
            Expected(id: "moonshotai/kimi-k3", contextWindow: 1_048_576, maxOutputTokens: 131_072, reasoningType: nil, effort: nil),
            Expected(id: "thinkingmachines/inkling", contextWindow: 1_048_576, maxOutputTokens: nil, reasoningType: .effort, effort: .high),
        ]

        let forbidden: ModelCapability = [.videoInput, .nativePDF, .codeExecution]
        for c in cases {
            let model = ModelCatalog.modelInfo(for: c.id, provider: .openrouter)
            XCTAssertEqual(model.contextWindow, c.contextWindow, c.id)
            XCTAssertEqual(model.maxOutputTokens, c.maxOutputTokens, c.id)
            XCTAssertTrue(model.capabilities.isDisjoint(with: forbidden), "\(c.id) must not claim video/PDF/code-exec on OpenRouter")
            XCTAssertEqual(model.reasoningConfig?.type, c.reasoningType, c.id)
            XCTAssertEqual(model.reasoningConfig?.defaultEffort, c.effort, c.id)
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: c.id, provider: .openrouter), c.id)
        }

        // Nano Banana 2 Lite outputs images but has no tool support on OpenRouter.
        let flashImage = ModelCatalog.modelInfo(for: "google/gemini-3.1-flash-lite-image", provider: .openrouter)
        XCTAssertTrue(flashImage.capabilities.contains(.imageGeneration))
        XCTAssertFalse(flashImage.capabilities.contains(.toolCalling))

        // Hy3 and Laguna are text-only.
        for id in ["tencent/hy3", "poolside/laguna-xs-2.1"] {
            XCTAssertFalse(ModelCatalog.modelInfo(for: id, provider: .openrouter).capabilities.contains(.vision), id)
        }

        // Kimi K3 is text+image only on OpenRouter (no audio), while Inkling is
        // text+image+audio; both expose cached-input pricing (verified 2026-07-18).
        let kimiK3 = ModelCatalog.modelInfo(for: "moonshotai/kimi-k3", provider: .openrouter)
        XCTAssertTrue(kimiK3.capabilities.contains(.vision))
        XCTAssertTrue(kimiK3.capabilities.contains(.toolCalling))
        XCTAssertTrue(kimiK3.capabilities.contains(.promptCaching))
        XCTAssertFalse(kimiK3.capabilities.contains(.audio))

        let inkling = ModelCatalog.modelInfo(for: "thinkingmachines/inkling", provider: .openrouter)
        XCTAssertTrue(inkling.capabilities.contains(.vision))
        XCTAssertTrue(inkling.capabilities.contains(.audio))
        XCTAssertTrue(inkling.capabilities.contains(.toolCalling))
        XCTAssertTrue(inkling.capabilities.contains(.promptCaching))
    }

    func testOpenRouterDots3NotePreviewExposesVerifiedCatalogMetadata() {
        // Live OpenRouter /models + /endpoints (2026-08-15): 512,000 / 512,000,
        // text+image->text, tools, toggle-only reasoning (no reasoning_effort),
        // no cache pricing. Official weights also understand audio/video; the
        // AtlasCloud OpenRouter route does not advertise those modalities.
        let id = "dots-studio/dots-3-note-preview:free"
        let forbidden: ModelCapability = [
            .audio, .videoInput, .promptCaching, .nativePDF, .codeExecution, .videoGeneration, .imageGeneration,
        ]

        let model = ModelCatalog.modelInfo(for: id, provider: .openrouter)
        XCTAssertEqual(model.name, "Dots Studio: Dots3-Note Preview (Free)")
        XCTAssertEqual(model.contextWindow, 512_000)
        XCTAssertEqual(model.maxOutputTokens, 512_000)
        XCTAssertEqual(model.reasoningConfig?.type, .toggle)
        XCTAssertNil(model.reasoningConfig?.defaultEffort)
        XCTAssertTrue(model.capabilities.contains(.streaming))
        XCTAssertTrue(model.capabilities.contains(.toolCalling))
        XCTAssertTrue(model.capabilities.contains(.vision))
        XCTAssertTrue(model.capabilities.contains(.reasoning))
        XCTAssertTrue(model.capabilities.isDisjoint(with: forbidden))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .openrouter))

        // Near-miss / dated / endpoint-less sibling slugs must stay conservative.
        for unknownID in [
            "dots-studio/dots-3-note-preview",
            "dots-studio/dots-3-note-preview-20260813",
            "dots-studio/dots-3-note-preview:free-custom",
        ] {
            let unknown = ModelCatalog.modelInfo(for: unknownID, provider: .openrouter)
            XCTAssertEqual(unknown.capabilities, [.streaming, .toolCalling], unknownID)
            XCTAssertEqual(unknown.contextWindow, 128_000, unknownID)
            XCTAssertNil(unknown.reasoningConfig, unknownID)
            XCTAssertFalse(
                ModelCatalog.isFullySupported(modelID: unknownID, provider: .openrouter),
                unknownID
            )
        }
    }
}
