import XCTest
@testable import Jin

final class ModelSettingsResolverTests: XCTestCase {
    func testModelInfoBackwardCompatibleDecodingWithoutOverrides() throws {
        let json = """
        {
          "id": "example/model",
          "name": "Example",
          "capabilities": 3,
          "contextWindow": 128000,
          "reasoningConfig": null,
          "isEnabled": true
        }
        """

        let decoded = try JSONDecoder().decode(ModelInfo.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, "example/model")
        XCTAssertNil(decoded.overrides)
    }

    func testResolverAppliesManualOverrides() {
        let model = ModelInfo(
            id: "openai/gpt-oss",
            name: "GPT OSS",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            reasoningConfig: nil,
            overrides: ModelOverrides(
                modelType: .chat,
                contextWindow: 256_000,
                maxOutputTokens: 12_000,
                capabilities: [.streaming, .toolCalling, .reasoning],
                reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
                reasoningCanDisable: false,
                webSearchSupported: false
            ),
            isEnabled: true
        )

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: .openrouter)
        XCTAssertEqual(resolved.contextWindow, 256_000)
        XCTAssertEqual(resolved.maxOutputTokens, 12_000)
        XCTAssertEqual(resolved.reasoningConfig?.type, .effort)
        XCTAssertEqual(resolved.reasoningConfig?.defaultEffort, .high)
        XCTAssertFalse(resolved.reasoningCanDisable)
        XCTAssertFalse(resolved.supportsWebSearch)
        XCTAssertEqual(resolved.requestShape, .openAICompatible)
        XCTAssertTrue(resolved.capabilities.contains(.reasoning))
    }

    func testOpenRouterUsesUnifiedRequestShapeAcrossModelFamilies() {
        let claudeModel = ModelInfo(
            id: "anthropic/claude-sonnet-4.6",
            name: "Claude Sonnet 4.6",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
        let geminiModel = ModelInfo(
            id: "google/gemini-2.5-pro",
            name: "Gemini 2.5 Pro",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
        let gptModel = ModelInfo(
            id: "openai/gpt-5",
            name: "GPT-5",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )

        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: claudeModel, providerType: .openrouter).requestShape,
            .openAICompatible
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: geminiModel, providerType: .openrouter).requestShape,
            .openAICompatible
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: gptModel, providerType: .openrouter).requestShape,
            .openAICompatible
        )
    }

    func testOpenAICompatibleUsesSelectedTypeWithoutModelNameShapeInference() {
        let claudeModel = ModelInfo(
            id: "anthropic/claude-sonnet-4.6",
            name: "Claude Sonnet 4.6",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
        let geminiModel = ModelInfo(
            id: "google/gemini-2.5-pro",
            name: "Gemini 2.5 Pro",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )

        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: claudeModel, providerType: .openaiCompatible).requestShape,
            .openAICompatible
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: geminiModel, providerType: .openaiCompatible).requestShape,
            .openAICompatible
        )
    }

    func testCloudflareAIGatewayUsesOpenAICompatibleRequestShape() {
        let claudeModel = ModelInfo(
            id: "anthropic/claude-sonnet-4.6",
            name: "Claude Sonnet 4.6",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
        let gptModel = ModelInfo(
            id: "openai/gpt-5.2",
            name: "GPT-5.2",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )

        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: claudeModel, providerType: .cloudflareAIGateway).requestShape,
            .openAICompatible
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: gptModel, providerType: .cloudflareAIGateway).requestShape,
            .openAICompatible
        )
    }

    func testZhipuCodingPlanUsesOpenAICompatibleRequestShapeAndCatalogReasoningFallback() {
        let legacyModel = ModelInfo(
            id: "glm-5",
            name: "GLM-5",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )

        let resolved = ModelSettingsResolver.resolve(model: legacyModel, providerType: .zhipuCodingPlan)

        XCTAssertEqual(resolved.requestShape, .openAICompatible)
        XCTAssertEqual(resolved.contextWindow, 200_000)
        XCTAssertEqual(resolved.reasoningConfig?.type, .toggle)
    }

    func testTogetherUsesOpenAICompatibleRequestShape() {
        let model = ModelInfo(
            id: "zai-org/GLM-5",
            name: "GLM-5",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )

        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: model, providerType: .together).requestShape,
            .openAICompatible
        )
    }

    func testOpenRouterDefaultReasoningConfigRecognizesGeminiAndClaudeModelIDs() {
        let gemini = ModelCapabilityRegistry.defaultReasoningConfig(
            for: .openrouter,
            modelID: "google/gemini-3-pro-preview"
        )
        let claude = ModelCapabilityRegistry.defaultReasoningConfig(
            for: .openrouter,
            modelID: "anthropic/claude-sonnet-4.6"
        )

        XCTAssertEqual(gemini?.type, .effort)
        XCTAssertEqual(claude?.type, .effort)
    }

    func testOpenAIStyleExtremeEffortSupportUsesExactModelIDs() {
        let gpt52pro = ModelInfo(
            id: "openai/gpt-5.2-pro",
            name: "GPT-5.2 Pro",
            capabilities: [.streaming, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )
        let gpt52codex = ModelInfo(
            id: "openai/gpt-5.2-codex",
            name: "GPT-5.2 Codex",
            capabilities: [.streaming, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )
        let gpt53codex = ModelInfo(
            id: "openai/gpt-5.3-codex",
            name: "GPT-5.3 Codex",
            capabilities: [.streaming, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )
        let gpt53codexSpark = ModelInfo(
            id: "openai/gpt-5.3-codex-spark",
            name: "GPT-5.3 Codex Spark",
            capabilities: [.streaming, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )
        let gpt52custom = ModelInfo(
            id: "openai/gpt-5.2-custom",
            name: "GPT-5.2 Custom",
            capabilities: [.streaming, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )
        let gpt5 = ModelInfo(
            id: "openai/gpt-5",
            name: "GPT-5",
            capabilities: [.streaming, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )

        XCTAssertTrue(ModelSettingsResolver.resolve(model: gpt52pro, providerType: .openrouter).supportsOpenAIStyleExtremeEffort)
        XCTAssertTrue(ModelSettingsResolver.resolve(model: gpt52codex, providerType: .openrouter).supportsOpenAIStyleExtremeEffort)
        XCTAssertTrue(ModelSettingsResolver.resolve(model: gpt53codex, providerType: .openrouter).supportsOpenAIStyleExtremeEffort)
        XCTAssertTrue(ModelSettingsResolver.resolve(model: gpt53codexSpark, providerType: .openrouter).supportsOpenAIStyleExtremeEffort)
        XCTAssertFalse(ModelSettingsResolver.resolve(model: gpt52custom, providerType: .openrouter).supportsOpenAIStyleExtremeEffort)
        XCTAssertFalse(ModelSettingsResolver.resolve(model: gpt5, providerType: .openrouter).supportsOpenAIStyleExtremeEffort)
    }

    func testReasoningEffortNormalizationClampsUnsupportedExtreme() {
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .openrouter, modelID: "openai/gpt-5"),
            .high
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .openrouter, modelID: "openai/gpt-5.2-pro"),
            .xhigh
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .openrouter, modelID: "openai/gpt-5.3-codex"),
            .xhigh
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .openrouter, modelID: "openai/gpt-5.3-codex-spark"),
            .xhigh
        )
    }

    func testGeminiAndVertexReasoningEffortSupportMatchesGemini3Families() {
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .gemini, modelID: "gemini-3-pro-preview"),
            [.low, .high]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .gemini, modelID: "gemini-3.1-pro-preview"),
            [.low, .medium, .high]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .gemini, modelID: "gemini-3-flash-preview"),
            [.minimal, .low, .medium, .high]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .vertexai, modelID: "gemini-3-pro-preview"),
            [.low, .high]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .vertexai, modelID: "gemini-3.1-pro-preview"),
            [.low, .medium, .high]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .gemini, modelID: "gemini-3.1-flash-image-preview"),
            [.minimal, .high]
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .vertexai, modelID: "gemini-3.1-flash-image-preview"),
            [.minimal, .high]
        )
    }

    func testGeminiAndVertexNormalizationClampsUnsupportedMinimalAndMedium() {
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.minimal, for: .vertexai, modelID: "gemini-3-pro-preview"),
            .low
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.medium, for: .vertexai, modelID: "gemini-3-pro-preview"),
            .high
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.minimal, for: .vertexai, modelID: "gemini-3.1-pro-preview"),
            .low
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.medium, for: .vertexai, modelID: "gemini-3.1-pro-preview"),
            .medium
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.minimal, for: .gemini, modelID: "gemini-3-pro-preview"),
            .low
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.medium, for: .gemini, modelID: "gemini-3-pro-preview"),
            .high
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.minimal, for: .gemini, modelID: "gemini-3.1-pro-preview"),
            .low
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.medium, for: .gemini, modelID: "gemini-3.1-pro-preview"),
            .medium
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.low, for: .gemini, modelID: "gemini-3.1-flash-image-preview"),
            .minimal
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.medium, for: .gemini, modelID: "gemini-3.1-flash-image-preview"),
            .high
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.low, for: .vertexai, modelID: "gemini-3.1-flash-image-preview"),
            .minimal
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.normalizedReasoningEffort(.medium, for: .vertexai, modelID: "gemini-3.1-flash-image-preview"),
            .high
        )
    }

    func testResolverSupportsExplicitReasoningDisableOverride() {
        let model = ModelInfo(
            id: "groq/openai/gpt-oss-120b",
            name: "GPT OSS 120B",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            overrides: ModelOverrides(
                reasoningConfig: ModelReasoningConfig(type: .none)
            ),
            isEnabled: true
        )

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: .groq)
        XCTAssertEqual(resolved.reasoningConfig?.type, ReasoningConfigType.none)
        XCTAssertTrue(resolved.capabilities.contains(.reasoning))
    }

    func testResolverDropsReasoningConfigWhenCapabilityDisabled() {
        let model = ModelInfo(
            id: "groq/openai/gpt-oss-120b",
            name: "GPT OSS 120B",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            overrides: ModelOverrides(
                capabilities: [.streaming, .toolCalling]
            ),
            isEnabled: true
        )

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: .groq)
        XCTAssertNil(resolved.reasoningConfig)
        XCTAssertFalse(resolved.capabilities.contains(.reasoning))
    }

    func testFireworksMiniMaxReasoningCannotDisableByDefault() {
        let model = ModelInfo(
            id: "fireworks/minimax-m2p5",
            name: "MiniMax",
            capabilities: [.streaming, .reasoning],
            contextWindow: 204_800,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: .fireworks)
        XCTAssertFalse(resolved.reasoningCanDisable)
    }

    func testSambaNovaAlwaysOnReasoningModelsCannotDisableByDefault() {
        let gptOSS = ModelInfo(
            id: "gpt-oss-120b",
            name: "GPT OSS 120B",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 131_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )
        let r1 = ModelInfo(
            id: "DeepSeek-R1-0528",
            name: "DeepSeek R1 0528",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 131_000,
            reasoningConfig: ModelReasoningConfig(type: .toggle),
            isEnabled: true
        )
        let r1Distill = ModelInfo(
            id: "DeepSeek-R1-Distill-Llama-70B",
            name: "DeepSeek R1 Distill",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 131_000,
            reasoningConfig: ModelReasoningConfig(type: .toggle),
            isEnabled: true
        )
        let v31 = ModelInfo(
            id: "DeepSeek-V3.1",
            name: "DeepSeek V3.1",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 131_000,
            reasoningConfig: ModelReasoningConfig(type: .toggle),
            isEnabled: true
        )

        XCTAssertFalse(ModelSettingsResolver.resolve(model: gptOSS, providerType: .sambanova).reasoningCanDisable)
        XCTAssertFalse(ModelSettingsResolver.resolve(model: r1, providerType: .sambanova).reasoningCanDisable)
        XCTAssertFalse(ModelSettingsResolver.resolve(model: r1Distill, providerType: .sambanova).reasoningCanDisable)
        XCTAssertTrue(ModelSettingsResolver.resolve(model: v31, providerType: .sambanova).reasoningCanDisable)
    }

    func testSambaNovaNearMatchDeepSeekR1ModelCanStillDisableReasoning() {
        let unknownNearMatch = ModelInfo(
            id: "custom-deepseek-r1-proxy",
            name: "Custom DeepSeek R1 Proxy",
            capabilities: [.streaming, .toolCalling, .reasoning],
            contextWindow: 131_000,
            reasoningConfig: ModelReasoningConfig(type: .toggle),
            isEnabled: true
        )

        let resolved = ModelSettingsResolver.resolve(model: unknownNearMatch, providerType: .sambanova)
        XCTAssertTrue(resolved.reasoningCanDisable)
    }

    func testResolverInfersGemini31ContextWindowForLegacyStoredModel() {
        let legacyModel = ModelInfo(
            id: "gemini-3.1-pro-preview",
            name: "Gemini 3.1 Pro Preview",
            capabilities: [.streaming, .toolCalling, .vision, .audio, .reasoning, .promptCaching, .nativePDF],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
            isEnabled: true
        )

        let resolvedGemini = ModelSettingsResolver.resolve(model: legacyModel, providerType: .gemini)
        XCTAssertEqual(resolvedGemini.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedGemini.reasoningConfig?.defaultEffort, .high)

        let resolvedVertex = ModelSettingsResolver.resolve(model: legacyModel, providerType: .vertexai)
        XCTAssertEqual(resolvedVertex.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedVertex.reasoningConfig?.defaultEffort, .medium)

        let legacyNanoBanana = ModelInfo(
            id: "gemini-3.1-flash-image-preview",
            name: "Gemini 3.1 Flash Image Preview",
            capabilities: [.streaming, .vision, .reasoning, .imageGeneration],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )

        let resolvedGeminiNanoBanana = ModelSettingsResolver.resolve(model: legacyNanoBanana, providerType: .gemini)
        XCTAssertEqual(resolvedGeminiNanoBanana.contextWindow, 131_072)
        XCTAssertEqual(resolvedGeminiNanoBanana.reasoningConfig?.defaultEffort, .minimal)

        let resolvedVertexNanoBanana = ModelSettingsResolver.resolve(model: legacyNanoBanana, providerType: .vertexai)
        XCTAssertEqual(resolvedVertexNanoBanana.contextWindow, 131_072)
        XCTAssertNil(resolvedVertexNanoBanana.reasoningConfig)

        let legacyProImage = ModelInfo(
            id: "gemini-3-pro-image-preview",
            name: "Gemini 3 Pro Image Preview",
            capabilities: [.streaming, .vision, .reasoning, .imageGeneration],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
            isEnabled: true
        )

        let resolvedGeminiProImage = ModelSettingsResolver.resolve(model: legacyProImage, providerType: .gemini)
        XCTAssertEqual(resolvedGeminiProImage.contextWindow, 65_536)
        XCTAssertNil(resolvedGeminiProImage.reasoningConfig)

        let resolvedVertexProImage = ModelSettingsResolver.resolve(model: legacyProImage, providerType: .vertexai)
        XCTAssertEqual(resolvedVertexProImage.contextWindow, 65_536)
        XCTAssertNil(resolvedVertexProImage.reasoningConfig)
    }

    func testResolverInfersContextWindowForKnownLegacyAnthropicPerplexityAndXAIModels() {
        let anthropicLegacy = ModelInfo(
            id: "claude-opus-4-6",
            name: "Claude Opus 4.6",
            capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
            contextWindow: 128_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
            isEnabled: true
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: anthropicLegacy, providerType: .anthropic).contextWindow,
            200_000
        )

        let perplexityLegacy = ModelInfo(
            id: "sonar-pro",
            name: "Sonar Pro",
            capabilities: [.streaming, .toolCalling, .vision],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: perplexityLegacy, providerType: .perplexity).contextWindow,
            200_000
        )

        let xaiLegacy = ModelInfo(
            id: "grok-imagine-image",
            name: "Grok Imagine Image",
            capabilities: [.imageGeneration],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: xaiLegacy, providerType: .xai).contextWindow,
            32_768
        )

        let xaiProLegacy = ModelInfo(
            id: "grok-imagine-image-pro",
            name: "Grok Imagine Image Pro",
            capabilities: [.imageGeneration],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: xaiProLegacy, providerType: .xai).contextWindow,
            32_768
        )
    }

    func testResolverInfersContextWindowAndReasoningForKnownLegacyTogetherModels() {
        let kimiLegacy = ModelInfo(
            id: "moonshotai/Kimi-K2.5",
            name: "Kimi K2.5",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )

        let resolvedKimi = ModelSettingsResolver.resolve(model: kimiLegacy, providerType: .together)
        XCTAssertEqual(resolvedKimi.contextWindow, 262_144)
        XCTAssertEqual(resolvedKimi.reasoningConfig?.type, .toggle)

        let glmLegacy = ModelInfo(
            id: "zai-org/GLM-5",
            name: "GLM-5",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )

        let resolvedGLM = ModelSettingsResolver.resolve(model: glmLegacy, providerType: .together)
        XCTAssertEqual(resolvedGLM.contextWindow, 202_752)
        XCTAssertEqual(resolvedGLM.reasoningConfig?.type, .toggle)
    }

    func testOpenRouterWebSearchDefaultsByModelFamily() {
        let gpt = ModelInfo(
            id: "openai/gpt-5",
            name: "GPT-5",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )
        let unknown = ModelInfo(
            id: "qwen/qwen3-32b",
            name: "Qwen 3",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil,
            isEnabled: true
        )

        XCTAssertTrue(ModelSettingsResolver.resolve(model: gpt, providerType: .openrouter).supportsWebSearch)
        XCTAssertFalse(ModelSettingsResolver.resolve(model: unknown, providerType: .openrouter).supportsWebSearch)
    }
}
