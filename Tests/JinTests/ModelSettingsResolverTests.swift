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

    func testResolverFallsBackToModelMaxOutputTokens() {
        let model = ModelInfo(
            id: "openai/gpt-4o",
            name: "GPT-4o",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000,
            maxOutputTokens: 16_384,
            reasoningConfig: nil,
            isEnabled: true
        )

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: .githubCopilot)
        XCTAssertEqual(resolved.maxOutputTokens, 16_384)
    }

    func testOpenAICatalogCarriesDocsVerifiedContextAndMaxOutput() {
        let gpt54 = ModelCatalog.modelInfo(for: "gpt-5.4", provider: .openai)
        let resolvedGPT54 = ModelSettingsResolver.resolve(model: gpt54, providerType: .openai)
        XCTAssertEqual(resolvedGPT54.contextWindow, 1_050_000)
        XCTAssertEqual(resolvedGPT54.maxOutputTokens, 128_000)

        let gpt52 = ModelCatalog.modelInfo(for: "gpt-5.2", provider: .openai)
        let resolvedGPT52 = ModelSettingsResolver.resolve(model: gpt52, providerType: .openai)
        XCTAssertEqual(resolvedGPT52.contextWindow, 400_000)
        XCTAssertEqual(resolvedGPT52.maxOutputTokens, 128_000)

        let gpt5 = ModelCatalog.modelInfo(for: "gpt-5", provider: .openai)
        let resolvedGPT5 = ModelSettingsResolver.resolve(model: gpt5, providerType: .openai)
        XCTAssertEqual(resolvedGPT5.contextWindow, 400_000)
        XCTAssertEqual(resolvedGPT5.maxOutputTokens, 128_000)

        let o3 = ModelCatalog.modelInfo(for: "o3", provider: .openai)
        let resolvedO3 = ModelSettingsResolver.resolve(model: o3, providerType: .openai)
        XCTAssertEqual(resolvedO3.contextWindow, 200_000)
        XCTAssertEqual(resolvedO3.maxOutputTokens, 100_000)

        let gpt4o = ModelCatalog.modelInfo(for: "gpt-4o", provider: .openai)
        let resolvedGPT4o = ModelSettingsResolver.resolve(model: gpt4o, providerType: .openai)
        XCTAssertEqual(resolvedGPT4o.contextWindow, 128_000)
        XCTAssertEqual(resolvedGPT4o.maxOutputTokens, 16_384)
    }

    func testAnthropicCatalogCarriesDocsVerifiedContextAndMaxOutput() {
        let opus46 = ModelCatalog.modelInfo(for: "claude-opus-4-6", provider: .anthropic)
        let resolvedOpus46 = ModelSettingsResolver.resolve(model: opus46, providerType: .anthropic)
        XCTAssertEqual(resolvedOpus46.contextWindow, 200_000)
        XCTAssertEqual(resolvedOpus46.maxOutputTokens, 128_000)

        let sonnet46 = ModelCatalog.modelInfo(for: "claude-sonnet-4-6", provider: .anthropic)
        let resolvedSonnet46 = ModelSettingsResolver.resolve(model: sonnet46, providerType: .anthropic)
        XCTAssertEqual(resolvedSonnet46.contextWindow, 200_000)
        XCTAssertEqual(resolvedSonnet46.maxOutputTokens, 64_000)

        let opus45 = ModelCatalog.modelInfo(for: "claude-opus-4-5-20251101", provider: .anthropic)
        let resolvedOpus45 = ModelSettingsResolver.resolve(model: opus45, providerType: .anthropic)
        XCTAssertEqual(resolvedOpus45.contextWindow, 200_000)
        XCTAssertEqual(resolvedOpus45.maxOutputTokens, 64_000)

        let haiku45 = ModelCatalog.modelInfo(for: "claude-haiku-4-5-20251001", provider: .anthropic)
        let resolvedHaiku45 = ModelSettingsResolver.resolve(model: haiku45, providerType: .anthropic)
        XCTAssertEqual(resolvedHaiku45.contextWindow, 200_000)
        XCTAssertEqual(resolvedHaiku45.maxOutputTokens, 64_000)
    }

    func testGeminiAndVertexCatalogCarryDocsVerifiedContextAndMaxOutput() {
        let gemini31Pro = ModelCatalog.modelInfo(for: "gemini-3.1-pro-preview", provider: .gemini)
        let resolvedGemini31Pro = ModelSettingsResolver.resolve(model: gemini31Pro, providerType: .gemini)
        XCTAssertEqual(resolvedGemini31Pro.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedGemini31Pro.maxOutputTokens, 65_536)

        let geminiImage = ModelCatalog.modelInfo(for: "gemini-2.5-flash-image", provider: .gemini)
        let resolvedGeminiImage = ModelSettingsResolver.resolve(model: geminiImage, providerType: .gemini)
        XCTAssertEqual(resolvedGeminiImage.contextWindow, 65_536)
        XCTAssertEqual(resolvedGeminiImage.maxOutputTokens, 32_768)

        let vertex25Pro = ModelCatalog.modelInfo(for: "gemini-2.5-pro", provider: .vertexai)
        let resolvedVertex25Pro = ModelSettingsResolver.resolve(model: vertex25Pro, providerType: .vertexai)
        XCTAssertEqual(resolvedVertex25Pro.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedVertex25Pro.maxOutputTokens, 65_535)

        let vertex25Flash = ModelCatalog.modelInfo(for: "gemini-2.5-flash", provider: .vertexai)
        let resolvedVertex25Flash = ModelSettingsResolver.resolve(model: vertex25Flash, providerType: .vertexai)
        XCTAssertEqual(resolvedVertex25Flash.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedVertex25Flash.maxOutputTokens, 65_535)

        let vertexFlashImage = ModelCatalog.modelInfo(for: "gemini-2.5-flash-image", provider: .vertexai)
        let resolvedVertexFlashImage = ModelSettingsResolver.resolve(model: vertexFlashImage, providerType: .vertexai)
        XCTAssertEqual(resolvedVertexFlashImage.contextWindow, 32_768)
        XCTAssertEqual(resolvedVertexFlashImage.maxOutputTokens, 32_768)
    }

    func testWrapperCatalogsMirrorDocsVerifiedOpenAIAnthropicAndGeminiLimits() {
        let cfGPT52 = ModelCatalog.modelInfo(for: "openai/gpt-5.2", provider: .cloudflareAIGateway)
        let resolvedCFGPT52 = ModelSettingsResolver.resolve(model: cfGPT52, providerType: .cloudflareAIGateway)
        XCTAssertEqual(resolvedCFGPT52.contextWindow, 400_000)
        XCTAssertEqual(resolvedCFGPT52.maxOutputTokens, 128_000)

        let cfO3 = ModelCatalog.modelInfo(for: "openai/o3", provider: .cloudflareAIGateway)
        let resolvedCFO3 = ModelSettingsResolver.resolve(model: cfO3, providerType: .cloudflareAIGateway)
        XCTAssertEqual(resolvedCFO3.contextWindow, 200_000)
        XCTAssertEqual(resolvedCFO3.maxOutputTokens, 100_000)

        let cfClaude46 = ModelCatalog.modelInfo(for: "anthropic/claude-opus-4-6", provider: .cloudflareAIGateway)
        let resolvedCFClaude46 = ModelSettingsResolver.resolve(model: cfClaude46, providerType: .cloudflareAIGateway)
        XCTAssertEqual(resolvedCFClaude46.contextWindow, 200_000)
        XCTAssertEqual(resolvedCFClaude46.maxOutputTokens, 128_000)

        let cfGemini31Pro = ModelCatalog.modelInfo(for: "google-vertex-ai/google/gemini-3.1-pro-preview", provider: .cloudflareAIGateway)
        let resolvedCFGemini31Pro = ModelSettingsResolver.resolve(model: cfGemini31Pro, providerType: .cloudflareAIGateway)
        XCTAssertEqual(resolvedCFGemini31Pro.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedCFGemini31Pro.maxOutputTokens, 65_536)

        let vercelClaude45 = ModelCatalog.modelInfo(for: "anthropic/claude-sonnet-4.5", provider: .vercelAIGateway)
        let resolvedVercelClaude45 = ModelSettingsResolver.resolve(model: vercelClaude45, providerType: .vercelAIGateway)
        XCTAssertEqual(resolvedVercelClaude45.contextWindow, 200_000)
        XCTAssertEqual(resolvedVercelClaude45.maxOutputTokens, 64_000)

        let vercelGemini31Pro = ModelCatalog.modelInfo(for: "google/gemini-3.1-pro-preview", provider: .vercelAIGateway)
        let resolvedVercelGemini31Pro = ModelSettingsResolver.resolve(model: vercelGemini31Pro, providerType: .vercelAIGateway)
        XCTAssertEqual(resolvedVercelGemini31Pro.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedVercelGemini31Pro.maxOutputTokens, 65_536)

        let vercelGemma431 = ModelCatalog.modelInfo(for: "google/gemma-4-31b-it", provider: .vercelAIGateway)
        let resolvedVercelGemma431 = ModelSettingsResolver.resolve(model: vercelGemma431, providerType: .vercelAIGateway)
        XCTAssertEqual(resolvedVercelGemma431.contextWindow, 262_144)
        XCTAssertEqual(resolvedVercelGemma431.maxOutputTokens, 131_072)
        XCTAssertEqual(resolvedVercelGemma431.reasoningConfig?.type, .effort)
        XCTAssertEqual(resolvedVercelGemma431.reasoningConfig?.defaultEffort, .medium)

        let openRouterGemini31Pro = ModelCatalog.modelInfo(for: "google/gemini-3.1-pro-preview", provider: .openrouter)
        let resolvedOpenRouterGemini31Pro = ModelSettingsResolver.resolve(model: openRouterGemini31Pro, providerType: .openrouter)
        XCTAssertEqual(resolvedOpenRouterGemini31Pro.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedOpenRouterGemini31Pro.maxOutputTokens, 65_536)

        let openRouterGemma426 = ModelCatalog.modelInfo(for: "google/gemma-4-26b-a4b-it", provider: .openrouter)
        let resolvedOpenRouterGemma426 = ModelSettingsResolver.resolve(model: openRouterGemma426, providerType: .openrouter)
        XCTAssertEqual(resolvedOpenRouterGemma426.contextWindow, 262_144)
        XCTAssertEqual(resolvedOpenRouterGemma426.maxOutputTokens, 262_144)
        XCTAssertEqual(resolvedOpenRouterGemma426.reasoningConfig?.type, .effort)
        XCTAssertEqual(resolvedOpenRouterGemma426.reasoningConfig?.defaultEffort, .medium)

        let geminiGemma431 = ModelCatalog.modelInfo(for: "gemma-4-31b-it", provider: .gemini)
        let resolvedGeminiGemma431 = ModelSettingsResolver.resolve(model: geminiGemma431, providerType: .gemini)
        XCTAssertEqual(resolvedGeminiGemma431.contextWindow, 262_144)
        XCTAssertNil(resolvedGeminiGemma431.maxOutputTokens)
        XCTAssertEqual(resolvedGeminiGemma431.reasoningConfig?.type, .effort)
        XCTAssertEqual(resolvedGeminiGemma431.reasoningConfig?.defaultEffort, .medium)
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

    func testVercelAIGatewayUsesOpenAICompatibleRequestShape() {
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
            ModelSettingsResolver.resolve(model: claudeModel, providerType: .vercelAIGateway).requestShape,
            .openAICompatible
        )
        XCTAssertEqual(
            ModelSettingsResolver.resolve(model: gptModel, providerType: .vercelAIGateway).requestShape,
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

    func testOpenAICompatibleDefaultReasoningConfigUsesDocsVerifiedOpenAIDefaults() {
        let gpt54Mini = ModelCapabilityRegistry.defaultReasoningConfig(
            for: .openrouter,
            modelID: "openai/gpt-5.4-mini"
        )
        let gpt54 = ModelCapabilityRegistry.defaultReasoningConfig(
            for: .vercelAIGateway,
            modelID: "openai/gpt-5.4"
        )
        let gpt54Pro = ModelCapabilityRegistry.defaultReasoningConfig(
            for: .openrouter,
            modelID: "openai/gpt-5.4-pro"
        )
        let gpt5 = ModelCapabilityRegistry.defaultReasoningConfig(
            for: .openrouter,
            modelID: "openai/gpt-5"
        )

        XCTAssertEqual(gpt54Mini?.type, .effort)
        XCTAssertEqual(gpt54Mini?.defaultEffort, ReasoningEffort.none)
        XCTAssertEqual(gpt54?.defaultEffort, ReasoningEffort.none)
        XCTAssertEqual(gpt54Pro?.defaultEffort, .high)
        XCTAssertEqual(gpt5?.defaultEffort, .medium)
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

    func testOpenAIGPT53ChatLatestCatalogMetadataKeepsReasoningDisabled() {
        let model = ModelCatalog.modelInfo(
            for: "gpt-5.3-chat-latest",
            provider: .openai
        )

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: .openai)
        XCTAssertFalse(resolved.capabilities.contains(.reasoning))
        XCTAssertNil(resolved.reasoningConfig)
        XCTAssertFalse(resolved.supportsOpenAIStyleExtremeEffort)
    }

    func testResolverAppliesCatalogMetadataForLegacyOpenAIGPT53ChatLatestModel() {
        let legacyModel = ModelInfo(
            id: "gpt-5.3-chat-latest",
            name: "GPT-5.3 Chat Latest",
            capabilities: [.streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF],
            contextWindow: 400_000,
            reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            isEnabled: true
        )

        let resolved = ModelSettingsResolver.resolve(model: legacyModel, providerType: .openai)
        XCTAssertEqual(resolved.contextWindow, 128_000)
        XCTAssertTrue(resolved.capabilities.contains(.streaming))
        XCTAssertTrue(resolved.capabilities.contains(.toolCalling))
        XCTAssertTrue(resolved.capabilities.contains(.vision))
        XCTAssertTrue(resolved.capabilities.contains(.promptCaching))
        XCTAssertFalse(resolved.capabilities.contains(.reasoning))
        XCTAssertFalse(resolved.capabilities.contains(.nativePDF))
        XCTAssertNil(resolved.reasoningConfig)
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
        XCTAssertEqual(resolvedVertexNanoBanana.reasoningConfig?.defaultEffort, .minimal)

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

    func testResolverInfersRecentTogetherCatalogMetadataForLegacyPersistedModels() {
        let deepSeekLegacy = ModelInfo(
            id: "deepseek-ai/DeepSeek-V3.1",
            name: "DeepSeek V3.1",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 8_192,
            reasoningConfig: nil,
            isEnabled: true
        )
        let resolvedDeepSeek = ModelSettingsResolver.resolve(model: deepSeekLegacy, providerType: .together)
        XCTAssertEqual(resolvedDeepSeek.contextWindow, 128_000)
        XCTAssertEqual(resolvedDeepSeek.reasoningConfig?.type, .toggle)

        let gptOSSLegacy = ModelInfo(
            id: "openai/gpt-oss-20b",
            name: "GPT OSS 20B",
            capabilities: [.streaming],
            contextWindow: 8_192,
            reasoningConfig: nil,
            isEnabled: true
        )
        let resolvedGPTOSS = ModelSettingsResolver.resolve(model: gptOSSLegacy, providerType: .together)
        XCTAssertEqual(resolvedGPTOSS.contextWindow, 128_000)
        XCTAssertEqual(resolvedGPTOSS.reasoningConfig?.type, .effort)
        XCTAssertEqual(resolvedGPTOSS.reasoningConfig?.defaultEffort, .medium)
        XCTAssertFalse(resolvedGPTOSS.reasoningCanDisable)

        let qwen35Legacy = ModelInfo(
            id: "Qwen/Qwen3.5-9B",
            name: "Qwen3.5 9B",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 8_192,
            reasoningConfig: nil,
            isEnabled: true
        )
        let resolvedQwen35 = ModelSettingsResolver.resolve(model: qwen35Legacy, providerType: .together)
        XCTAssertEqual(resolvedQwen35.contextWindow, 262_144)
        XCTAssertTrue(resolvedQwen35.capabilities.contains(.vision))
        XCTAssertEqual(resolvedQwen35.reasoningConfig?.type, .toggle)
        XCTAssertTrue(resolvedQwen35.reasoningCanDisable)
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

    func testOpenRouterCatalogCarriesLatestXiaomiAndMiniMaxMetadata() {
        let mimoOmni = ModelCatalog.modelInfo(for: "xiaomi/mimo-v2-omni", provider: .openrouter)
        let resolvedMimoOmni = ModelSettingsResolver.resolve(model: mimoOmni, providerType: .openrouter)
        XCTAssertEqual(resolvedMimoOmni.contextWindow, 262_144)
        XCTAssertEqual(resolvedMimoOmni.maxOutputTokens, 65_536)
        XCTAssertTrue(resolvedMimoOmni.capabilities.contains(.vision))
        XCTAssertTrue(resolvedMimoOmni.capabilities.contains(.audio))
        XCTAssertTrue(resolvedMimoOmni.capabilities.contains(.reasoning))

        let mimoPro = ModelCatalog.modelInfo(for: "xiaomi/mimo-v2-pro", provider: .openrouter)
        let resolvedMimoPro = ModelSettingsResolver.resolve(model: mimoPro, providerType: .openrouter)
        XCTAssertEqual(resolvedMimoPro.contextWindow, 1_048_576)
        XCTAssertEqual(resolvedMimoPro.maxOutputTokens, 131_072)
        XCTAssertFalse(resolvedMimoPro.capabilities.contains(.vision))
        XCTAssertTrue(resolvedMimoPro.capabilities.contains(.reasoning))

        let miniMaxM27 = ModelCatalog.modelInfo(for: "minimax/minimax-m2.7", provider: .openrouter)
        let resolvedMiniMaxM27 = ModelSettingsResolver.resolve(model: miniMaxM27, providerType: .openrouter)
        XCTAssertEqual(resolvedMiniMaxM27.contextWindow, 204_800)
        XCTAssertEqual(resolvedMiniMaxM27.maxOutputTokens, 131_072)
        XCTAssertTrue(resolvedMiniMaxM27.capabilities.contains(.toolCalling))
        XCTAssertTrue(resolvedMiniMaxM27.capabilities.contains(.reasoning))

        let miniMaxM25Free = ModelCatalog.modelInfo(for: "minimax/minimax-m2.5:free", provider: .openrouter)
        let resolvedMiniMaxM25Free = ModelSettingsResolver.resolve(model: miniMaxM25Free, providerType: .openrouter)
        XCTAssertEqual(resolvedMiniMaxM25Free.contextWindow, 196_608)
        XCTAssertEqual(resolvedMiniMaxM25Free.maxOutputTokens, 196_608)
        XCTAssertTrue(resolvedMiniMaxM25Free.capabilities.contains(.reasoning))

        let miniMax01 = ModelCatalog.modelInfo(for: "minimax/minimax-01", provider: .openrouter)
        let resolvedMiniMax01 = ModelSettingsResolver.resolve(model: miniMax01, providerType: .openrouter)
        XCTAssertEqual(resolvedMiniMax01.contextWindow, 1_000_192)
        XCTAssertEqual(resolvedMiniMax01.maxOutputTokens, 1_000_192)
        XCTAssertTrue(resolvedMiniMax01.capabilities.contains(.vision))
        XCTAssertFalse(resolvedMiniMax01.capabilities.contains(.reasoning))
    }

}
