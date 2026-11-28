import XCTest
@testable import Jin

final class November2026ModelCensusRegressionTests: XCTestCase {

    // MARK: - OpenAI Healthcare (Nov 24)

    func testOpenAIHealthcareModelsMetadataAndCapabilities() {
        let healthcareIDs = [
            "gpt-6.2-astra-healthcare",
            "gpt-6.2-sol-healthcare",
            "gpt-6-astra-healthcare",
            "gpt-6.1-sol-healthcare",
        ]

        for id in healthcareIDs {
            for provider in [ProviderType.openai, .openaiWebSocket] {
                XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: provider), "\(provider): \(id)")
                let info = ModelCatalog.modelInfo(for: id, provider: provider)
                XCTAssertEqual(info.contextWindow, 1_050_000, id)
                XCTAssertEqual(info.maxOutputTokens, 128_000, id)
                XCTAssertTrue(info.capabilities.contains(.streaming), id)
                XCTAssertTrue(info.capabilities.contains(.toolCalling), id)
                XCTAssertTrue(info.capabilities.contains(.vision), id)
                XCTAssertTrue(info.capabilities.contains(.reasoning), id)
                XCTAssertTrue(info.capabilities.contains(.promptCaching), id)
                XCTAssertTrue(info.capabilities.contains(.nativePDF), id)
                XCTAssertFalse(info.capabilities.contains(.codeExecution), id)
                XCTAssertEqual(
                    ModelCapabilityRegistry.supportedReasoningEfforts(for: provider, modelID: id),
                    [.low, .medium, .high, .xhigh, .max],
                    id
                )
                XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: provider, modelID: id), id)
                XCTAssertTrue(ModelCapabilityRegistry.supportsOpenAIStyleVerbosity(for: provider, modelID: id), id)
                XCTAssertFalse(
                    ModelSettingsResolver.resolve(model: info, providerType: provider).reasoningCanDisable,
                    id
                )
                XCTAssertFalse(
                    supportsOpenAIResponsesSamplingParameters(modelID: id, reasoningEnabled: true, providerType: provider),
                    id
                )
            }
        }
    }

    // MARK: - Zhipu Coding Plan GLM-5.4 (Nov 23)

    func testZhipuGLM54MetadataAndLegacyResolution() {
        let info = ModelCatalog.modelInfo(for: "glm-5.4", provider: .zhipuCodingPlan)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "glm-5.4", provider: .zhipuCodingPlan))
        XCTAssertEqual(info.contextWindow, 1_000_000)
        XCTAssertEqual(info.maxOutputTokens, 131_072)
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.toolCalling))
        XCTAssertTrue(info.capabilities.contains(.promptCaching))
        XCTAssertFalse(info.capabilities.contains(.videoInput))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .zhipuCodingPlan, modelID: "glm-5.4"),
            [.low, .high, .max]
        )
        XCTAssertFalse(
            ModelSettingsResolver.resolve(model: info, providerType: .zhipuCodingPlan).reasoningCanDisable
        )

        // Legacy persisted model without overrides inherits catalog limits and reasoning lock.
        let legacy = ModelInfo(
            id: "glm-5.4",
            name: "GLM-5.4",
            capabilities: [.streaming],
            contextWindow: 128_000,
            reasoningConfig: nil
        )
        let resolved = ModelSettingsResolver.resolve(model: legacy, providerType: .zhipuCodingPlan)
        XCTAssertEqual(resolved.contextWindow, 1_000_000)
        XCTAssertEqual(resolved.maxOutputTokens, 131_072)
        XCTAssertFalse(resolved.reasoningCanDisable)
    }

    // MARK: - OpenRouter (Nov 20–26)

    func testOpenRouterNovemberAdditions() {
        let lingsante = ModelCatalog.modelInfo(for: "inclusionai/lingsante-3.1-air-vl", provider: .openrouter)
        XCTAssertEqual(lingsante.contextWindow, 131_072)
        XCTAssertEqual(lingsante.maxOutputTokens, 32_768)
        XCTAssertEqual(lingsante.reasoningConfig?.type, .toggle)
        XCTAssertTrue(lingsante.capabilities.contains(.vision))
        XCTAssertTrue(lingsante.capabilities.contains(.promptCaching))

        for solarID in ["upstage/solar-pro-4-contributor", "upstage/solar-mini-4-5"] {
            let solar = ModelCatalog.modelInfo(for: solarID, provider: .openrouter)
            XCTAssertEqual(solar.contextWindow, 524_288, solarID)
            XCTAssertEqual(solar.maxOutputTokens, 131_072, solarID)
            XCTAssertFalse(solar.capabilities.contains(.vision), solarID)
            XCTAssertEqual(
                ModelCapabilityRegistry.supportedReasoningEfforts(for: .openrouter, modelID: solarID),
                [.none, .minimal, .low, .medium, .high, .xhigh, .max],
                solarID
            )
        }

        let mimo = ModelCatalog.modelInfo(for: "xiaomi/mimo-v2.6-flash-mopd", provider: .openrouter)
        XCTAssertEqual(mimo.contextWindow, 1_048_576)
        XCTAssertEqual(mimo.maxOutputTokens, 32_768)
        XCTAssertTrue(mimo.capabilities.contains(.audio))
        XCTAssertFalse(mimo.capabilities.contains(.videoInput))

        let inkling = ModelCatalog.modelInfo(for: "thinkingmachines/inkling-2-mini", provider: .openrouter)
        XCTAssertEqual(inkling.contextWindow, 1_048_576)
        XCTAssertEqual(inkling.maxOutputTokens, 65_536)
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .openrouter, modelID: "thinkingmachines/inkling-2-mini"),
            [.none, .minimal, .low, .medium, .high, .max]
        )

        let daisy = ModelCatalog.modelInfo(for: "radixark/daisyrose-27b", provider: .openrouter)
        XCTAssertEqual(daisy.contextWindow, 262_144)
        XCTAssertEqual(daisy.maxOutputTokens, 235_929)
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .openrouter, modelID: "radixark/daisyrose-27b"),
            [.none, .low, .medium, .xhigh]
        )

        let pixtral = ModelCatalog.modelInfo(for: "mistralai/pixtral-large-2502", provider: .openrouter)
        XCTAssertEqual(pixtral.contextWindow, 128_000)
        XCTAssertEqual(pixtral.maxOutputTokens, 102_400)
        XCTAssertEqual(pixtral.capabilities, [.streaming, .vision])
        XCTAssertNil(pixtral.reasoningConfig)
    }

    // MARK: - Vercel AI Gateway (Nov 24)

    func testVercelInkling2MiniOmitsTopPAndExposesFullEffortBand() {
        let id = "thinkingmachines/inkling-2-mini"
        let info = ModelCatalog.modelInfo(for: id, provider: .vercelAIGateway)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .vercelAIGateway))
        XCTAssertEqual(info.contextWindow, 1_048_576)
        XCTAssertEqual(info.maxOutputTokens, 1_000_000)
        XCTAssertTrue(info.capabilities.contains(.vision))
        XCTAssertTrue(info.capabilities.contains(.promptCaching))
        XCTAssertFalse(ModelCapabilityRegistry.supportsTopP(for: .vercelAIGateway, modelID: id))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .vercelAIGateway, modelID: id),
            [.none, .minimal, .low, .medium, .high, .xhigh, .max]
        )
    }

    // MARK: - DeepInfra (Nov 20–26)

    func testDeepInfraNovemberAdditions() {
        let expected: [(String, Int)] = [
            ("inclusionAI/LingSante-3.1-air-VL", 131_072),
            ("thinkingmachines/Inkling-2-Mini", 1_048_576),
            ("tencent/Hy4-flash", 1_048_576),
            ("tencent/Hy4", 1_048_576),
            ("RadixArk/DaisyRose-27B", 262_144),
        ]
        for (id, ctx) in expected {
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .deepinfra), id)
            let info = ModelCatalog.modelInfo(for: id, provider: .deepinfra)
            XCTAssertEqual(info.contextWindow, ctx, id)
            XCTAssertTrue(info.capabilities.contains(.vision), id)
            XCTAssertTrue(info.capabilities.contains(.toolCalling), id)
            XCTAssertTrue(info.capabilities.contains(.promptCaching), id)
            XCTAssertFalse(info.capabilities.contains(.videoInput), id)
            XCTAssertEqual(info.reasoningConfig?.type, .toggle, id)
        }
    }

    // MARK: - Together AI (Nov 23)

    func testTogetherDeepSeekV41Flash1017Fast() {
        let id = "deepseek-ai/DeepSeek-V4.1-Flash-1017-fast"
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .together))
        let info = ModelCatalog.modelInfo(for: id, provider: .together)
        XCTAssertEqual(info.contextWindow, 1_000_000)
        XCTAssertEqual(info.maxOutputTokens, 384_000)
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .together, modelID: id),
            [.low, .high, .max]
        )
        XCTAssertFalse(ModelSettingsResolver.resolve(model: info, providerType: .together).reasoningCanDisable)
    }

    // MARK: - Fireworks (Nov 20–25)

    func testFireworksNovemberAdditionsAndRouterModes() {
        let hy4 = ModelCatalog.modelInfo(for: "accounts/fireworks/models/hy4-flash", provider: .fireworks)
        XCTAssertEqual(hy4.contextWindow, 524_288)
        XCTAssertTrue(hy4.capabilities.contains(.vision))

        for inklingID in ["accounts/fireworks/models/inkling-2-mini", "accounts/fireworks/models/inkling-2-small"] {
            let info = ModelCatalog.modelInfo(for: inklingID, provider: .fireworks)
            XCTAssertEqual(info.contextWindow, 1_048_576, inklingID)
            XCTAssertTrue(info.capabilities.contains(.vision), inklingID)
        }

        let alwaysOnRouters = [
            "accounts/fireworks/routers/kimi-k3p1-pro-ultrafast",
            "accounts/fireworks/routers/glm-5p3-flex",
            "accounts/fireworks/routers/glm-5p3-flash-flex",
        ]
        for id in alwaysOnRouters {
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: id, provider: .fireworks), id)
            let info = ModelCatalog.modelInfo(for: id, provider: .fireworks)
            XCTAssertEqual(
                ModelCapabilityRegistry.supportedReasoningEfforts(for: .fireworks, modelID: id),
                [.low, .high, .max],
                id
            )
            XCTAssertFalse(ModelSettingsResolver.resolve(model: info, providerType: .fireworks).reasoningCanDisable, id)
        }
        XCTAssertTrue(isFireworksGLM53Model("accounts/fireworks/routers/glm-5p3-flex"))
        XCTAssertTrue(isFireworksGLM53Model("accounts/fireworks/routers/glm-5p3-flash-flex"))
    }

    // MARK: - Databricks Unity Gateway & Kimi Fast (Nov 25)

    func testDatabricksGemini4NeonAndKimiK31ProFastRoutingAndSpecs() async throws {
        let neon = ModelCatalog.modelInfo(for: "system.ai.gemini-4-neon", provider: .databricks)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "system.ai.gemini-4-neon", provider: .databricks))
        XCTAssertEqual(neon.contextWindow, 1_048_576)
        XCTAssertEqual(neon.maxOutputTokens, 65_536)
        XCTAssertTrue(neon.capabilities.contains(.vision))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .databricks, modelID: "system.ai.gemini-4-neon"),
            [.low, .medium, .high]
        )
        XCTAssertFalse(ModelSettingsResolver.resolve(model: neon, providerType: .databricks).reasoningCanDisable)

        for kimiID in ["system.ai.kimi-k3-1-pro-fast", "databricks-kimi-k3-1-pro-fast"] {
            let info = ModelCatalog.modelInfo(for: kimiID, provider: .databricks)
            XCTAssertTrue(ModelCatalog.isFullySupported(modelID: kimiID, provider: .databricks), kimiID)
            XCTAssertEqual(info.contextWindow, 1_048_576, kimiID)
            XCTAssertEqual(
                ModelCapabilityRegistry.supportedReasoningEfforts(for: .databricks, modelID: kimiID),
                [.none, .low, .high, .max],
                kimiID
            )
            XCTAssertTrue(ModelSettingsResolver.resolve(model: info, providerType: .databricks).reasoningCanDisable, kimiID)
        }

        let config = ProviderConfig(
            id: "databricks",
            name: "Databricks",
            type: .databricks,
            apiKey: "test-key",
            baseURL: "https://dbc-test.cloud.databricks.com/serving-endpoints",
            models: [neon]
        )
        let adapter = DatabricksAdapter(providerConfig: config, apiKey: "test-key")
        let controls = GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))
        let neonReq = try await adapter.buildRequest(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "system.ai.gemini-4-neon",
            controls: controls,
            tools: [],
            streaming: true
        )
        XCTAssertEqual(
            neonReq.url?.absoluteString,
            "https://dbc-test.cloud.databricks.com/ai-gateway/mlflow/v1/chat/completions"
        )
        let neonBody = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(neonReq.httpBody)) as? [String: Any])
        XCTAssertEqual(neonBody["reasoning_effort"] as? String, "high")

        let kimiUnityReq = try await adapter.buildRequest(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "system.ai.kimi-k3-1-pro-fast",
            controls: controls,
            tools: [],
            streaming: true
        )
        XCTAssertEqual(
            kimiUnityReq.url?.absoluteString,
            "https://dbc-test.cloud.databricks.com/ai-gateway/mlflow/v1/chat/completions"
        )
    }

    // MARK: - RunInfra, OpenCode Go, MorphLLM

    func testRunInfraOpenCodeGoAndMorphLLMAdditions() {
        let writing = ModelCatalog.modelInfo(for: "rightnow-writing-1", provider: .runinfra)
        XCTAssertEqual(writing.contextWindow, 1_048_576)
        XCTAssertFalse(writing.capabilities.contains(.toolCalling))
        XCTAssertFalse(writing.capabilities.contains(.promptCaching))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .runinfra, modelID: "rightnow-writing-1"),
            [.none, .low, .high, .xhigh, .max]
        )

        for kimiID in ["kimi-k3-1-pro", "moonshotai/Kimi-K3.1-Pro"] {
            let info = ModelCatalog.modelInfo(for: kimiID, provider: .runinfra)
            XCTAssertEqual(info.contextWindow, 1_048_576, kimiID)
            XCTAssertEqual(info.maxOutputTokens, 32_768, kimiID)
            XCTAssertTrue(info.capabilities.contains(.vision), kimiID)
            XCTAssertTrue(info.capabilities.contains(.promptCaching), kimiID)
            XCTAssertEqual(
                ModelCapabilityRegistry.supportedReasoningEfforts(for: .runinfra, modelID: kimiID),
                [.low, .high, .max],
                kimiID
            )
            XCTAssertFalse(ModelSettingsResolver.resolve(model: info, providerType: .runinfra).reasoningCanDisable, kimiID)
        }

        let hungerg = ModelCatalog.modelInfo(for: "hungerg-free", provider: .opencodeGo)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "hungerg-free", provider: .opencodeGo))
        XCTAssertEqual(hungerg.contextWindow, 1_000_000)
        XCTAssertEqual(hungerg.maxOutputTokens, 65_536)
        XCTAssertTrue(hungerg.capabilities.contains(.vision))
        XCTAssertFalse(hungerg.capabilities.contains(.videoInput))
        XCTAssertEqual(hungerg.reasoningConfig?.type, .toggle)

        let morph = ModelCatalog.modelInfo(for: "morph-kimik3-abliterated", provider: .morphllm)
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "morph-kimik3-abliterated", provider: .morphllm))
        XCTAssertEqual(morph.contextWindow, 1_048_576)
        XCTAssertEqual(morph.maxOutputTokens, 1_048_576)
        XCTAssertEqual(morph.capabilities, [.streaming])
    }
}
