import XCTest
@testable import Jin

/// Claude Haiku 5.5 (`claude-haiku-5-5`, released 2026-10-07). Unlike Sonnet 5.5,
/// thinking can be disabled at effort high or below, and xhigh/max paired with a
/// disabled block must be clamped. The prefix is `claude-haiku-5-5`, not
/// `claude-haiku-5`. Gateway copies keep the exact IDs their own docs publish.
final class AnthropicHaiku55SupportTests: XCTestCase {

    func testHaiku55CatalogRecordIsSeededAheadOfHaiku45WithVerifiedLimits() throws {
        let seeded = ModelCatalog.seededModels(for: .anthropic)
        let haiku = try XCTUnwrap(
            seeded.first(where: { $0.id == "claude-haiku-5-5" }),
            "Haiku 5.5 must be seeded so it appears in the picker on first launch"
        )

        XCTAssertEqual(haiku.name, "Claude Haiku 5.5")
        XCTAssertEqual(haiku.contextWindow, 1_000_000)
        XCTAssertEqual(haiku.maxOutputTokens, 128_000)
        XCTAssertEqual(haiku.reasoningConfig?.type, .effort)
        XCTAssertEqual(haiku.reasoningConfig?.defaultEffort, .medium)
        for capability: ModelCapability in [
            .streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution,
        ] {
            XCTAssertTrue(haiku.capabilities.contains(capability), "\(capability)")
        }
        // PDF support: every active Claude model accepts document blocks, including
        // this one (600 pages on the 1M window). The overview line only says text and images.
        XCTAssertFalse(haiku.capabilities.contains(.videoInput))
        XCTAssertFalse(haiku.capabilities.contains(.audio))

        let ids = seeded.map(\.id)
        let index55 = try XCTUnwrap(ids.firstIndex(of: "claude-haiku-5-5"))
        let index45 = try XCTUnwrap(ids.firstIndex(of: "claude-haiku-4-5-20251001"))
        XCTAssertLessThan(index55, index45, "newest Haiku leads its tier in the picker")
    }

    func testHaiku55IsFullySupportedOnAnthropicAndManagedAgentsButNearMissesAreNot() {
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "claude-haiku-5-5", provider: .anthropic))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "claude-haiku-5-5", provider: .claudeManagedAgents))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .anthropic, modelID: "claude-haiku-5-5"))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .claudeManagedAgents, modelID: "claude-haiku-5-5"))
        for id in [
            "claude-haiku-5",
            "claude-haiku-5-5-custom",
            "claude-haiku-55",
            "claude-haiku-5.5",
            "anthropic/claude-haiku-5.5",
        ] {
            XCTAssertFalse(ModelCatalog.isFullySupported(modelID: id, provider: .anthropic), id)
        }
        // `claude-haiku-5` is a fixture ID. The dotted gateway slug is a different surface.
        // A hyphenated extra suffix (`-custom`, a dated snapshot) still matches the family.
        for id in ["claude-haiku-5", "claude-haiku-55", "claude-haiku-5.5", "anthropic/claude-haiku-5.5"] {
            XCTAssertFalse(AnthropicModelLimits.isHaiku55(id), id)
        }
        XCTAssertTrue(AnthropicModelLimits.isHaiku55("claude-haiku-5-5-custom"))
        // A dated snapshot shares the family surface but is not the seeded catalog ID.
        XCTAssertTrue(AnthropicModelLimits.isHaiku55("claude-haiku-5-5-20261007"))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "claude-haiku-5-5-20261007", provider: .anthropic))
    }

    func testHaiku55IsTheHaikuHeadWithoutReorderingOpusOrSonnet() throws {
        let order = ChatModelSelectionSupport.preferredAnthropicModelOrder
        XCTAssertEqual(order.first, "claude-opus-5-5")
        let sonnet55 = try XCTUnwrap(order.firstIndex(of: "claude-sonnet-5-5"))
        let sonnet5 = try XCTUnwrap(order.firstIndex(of: "claude-sonnet-5"))
        let sonnet45 = try XCTUnwrap(order.firstIndex(of: "claude-sonnet-4-5-20250929"))
        let haiku = try XCTUnwrap(order.firstIndex(of: "claude-haiku-5-5"))
        XCTAssertLessThan(sonnet55, sonnet5)
        XCTAssertLessThan(sonnet45, haiku)
    }

    func testHaiku55CanDisableThinkingAndClampsXHighAndMax() throws {
        XCTAssertTrue(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-haiku-5-5"))
        XCTAssertTrue(AnthropicModelLimits.requiresExplicitThinkingDisabled(for: "claude-haiku-5-5"))
        XCTAssertTrue(AnthropicModelLimits.disabledThinkingRequiresEffortAtMostHigh(for: "claude-haiku-5-5"))
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .anthropic, modelID: "claude-haiku-5-5"))
        XCTAssertTrue(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .claudeManagedAgents, modelID: "claude-haiku-5-5")
        )
        XCTAssertFalse(AnthropicModelLimits.requiresExplicitThinkingDisabled(for: "claude-haiku-5"))
        XCTAssertFalse(AnthropicModelLimits.disabledThinkingRequiresEffortAtMostHigh(for: "claude-haiku-5.5"))

        var disabled: [String: Any] = [:]
        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &disabled,
            controls: GenerationControls(
                temperature: 0.4,
                topP: 0.8,
                reasoning: ReasoningControls(enabled: false)
            ),
            providerType: .anthropic,
            modelID: "claude-haiku-5-5"
        )
        let thinking = try XCTUnwrap(disabled["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "disabled")
        XCTAssertNil(disabled["temperature"])
        XCTAssertNil(disabled["top_p"])

        for effort in ["xhigh", "max"] {
            var body: [String: Any] = [
                "thinking": ["type": "disabled"],
                "output_config": ["effort": effort],
            ]
            AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &body, modelID: "claude-haiku-5-5")
            let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
            XCTAssertEqual(outputConfig["effort"] as? String, "high", effort)
        }

        var allowed: [String: Any] = [
            "thinking": ["type": "disabled"],
            "output_config": ["effort": "medium"],
        ]
        AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &allowed, modelID: "claude-haiku-5-5")
        XCTAssertEqual((allowed["output_config"] as? [String: Any])?["effort"] as? String, "medium")

        var adaptive: [String: Any] = [
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "max"],
        ]
        AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &adaptive, modelID: "claude-haiku-5-5")
        XCTAssertEqual((adaptive["output_config"] as? [String: Any])?["effort"] as? String, "max")
    }

    func testHaiku55ApiSurfaceMatchesTheDocumentedLadder() throws {
        XCTAssertFalse(AnthropicModelLimits.supportsSamplingParameters(for: "claude-haiku-5-5"))
        XCTAssertTrue(AnthropicModelLimits.requiresExplicitThinkingDisplay(for: "claude-haiku-5-5"))
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-haiku-5-5"), 128_000)
        XCTAssertTrue(AnthropicModelLimits.supportsXHighEffort(for: "claude-haiku-5-5"))
        XCTAssertTrue(AnthropicModelLimits.supportsMaxEffort(for: "claude-haiku-5-5"))
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-haiku-5-5"))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: "claude-haiku-5-5"),
            [.low, .medium, .high, .xhigh, .max]
        )

        var body: [String: Any] = [:]
        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max)),
            providerType: .anthropic,
            modelID: "claude-haiku-5-5"
        )
        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "adaptive")
        XCTAssertEqual(thinking["display"] as? String, "summarized")
        XCTAssertNil(thinking["budget_tokens"])
        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "max")
    }

    func testHaiku55ServerToolsAreAnthropicOnly() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-haiku-5-5"))
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-haiku-5-5-custom")
        )
        XCTAssertFalse(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-haiku-5"))
        for provider in [
            ProviderType.claudeManagedAgents, .opencodeGo, .openrouter, .vercelAIGateway,
            .databricks, .router, .githubCopilot,
        ] {
            XCTAssertFalse(
                ModelCapabilityRegistry.supportsCodeExecution(for: provider, modelID: "claude-haiku-5-5"),
                "\(provider)"
            )
        }
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: "claude-haiku-5-5"))
        XCTAssertFalse(ModelCapabilityRegistry.supportsWebSearch(for: .claudeManagedAgents, modelID: "claude-haiku-5-5"))
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: "claude-haiku-5-5")
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
                for: .anthropic,
                modelID: "claude-haiku-5-5-custom"
            )
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsWebSearch(for: .vercelAIGateway, modelID: "anthropic/claude-haiku-5.5")
        )
        // OpenRouter already enables web search for every `anthropic/` ID. This copy
        // inherits that prefix; the Haiku page itself is not a new web-search claim.
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearch(for: .openrouter, modelID: "anthropic/claude-haiku-5.5")
        )
    }

    func testLegacyPersistedHaiku55RowResolvesToCatalogSpecs() {
        let legacy = ModelInfo(
            id: "claude-haiku-5-5",
            name: "claude-haiku-5-5",
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128_000
        )

        for providerType in [ProviderType.anthropic, .claudeManagedAgents] {
            let resolved = ModelSettingsResolver.resolve(model: legacy, providerType: providerType)
            XCTAssertEqual(resolved.contextWindow, 1_000_000, "\(providerType)")
            XCTAssertEqual(resolved.maxOutputTokens, 128_000, "\(providerType)")
            XCTAssertTrue(
                resolved.capabilities.isSuperset(of: [.vision, .reasoning, .promptCaching, .nativePDF, .codeExecution]),
                "\(providerType)"
            )
            XCTAssertEqual(resolved.reasoningConfig?.type, .effort, "\(providerType)")
            XCTAssertEqual(resolved.reasoningConfig?.defaultEffort, .medium, "\(providerType)")
            XCTAssertTrue(resolved.reasoningCanDisable, "\(providerType)")
        }
    }

    func testOpenCodeGoRoutesHaiku55ToMessagesAndDoesNotTreatItAsAlwaysOn() throws {
        XCTAssertTrue(OpenCodeGoAdapter.usesAnthropicMessagesEndpoint("claude-haiku-5-5"))
        XCTAssertFalse(OpenCodeGoAdapter.usesAnthropicMessagesEndpoint("claude-haiku-5"))
        XCTAssertFalse(OpenCodeGoAdapter.usesAnthropicMessagesEndpoint("claude-haiku-5.5"))
        XCTAssertFalse(OpenCodeGoAdapter.usesAnthropicMessagesEndpoint("claude-haiku-5-5-custom"))

        let seeded = ModelCatalog.seededModels(for: .opencodeGo)
        XCTAssertEqual(seeded.first?.id, "glm-5.3")
        let haiku = try XCTUnwrap(seeded.first(where: { $0.id == "claude-haiku-5-5" }))
        XCTAssertEqual(haiku.contextWindow, 1_000_000)
        XCTAssertEqual(haiku.maxOutputTokens, 128_000)
        XCTAssertEqual(haiku.reasoningConfig?.defaultEffort, .medium)
        XCTAssertEqual(
            haiku.reasoningConfig?.supportedEfforts,
            [.low, .medium, .high, .xhigh, .max]
        )
        XCTAssertFalse(haiku.capabilities.contains(.nativePDF))
        XCTAssertFalse(haiku.capabilities.contains(.codeExecution))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "claude-haiku-5-5", provider: .opencodeGo))
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .opencodeGo, modelID: "claude-haiku-5-5"))
    }

    func testGatewayCopiesUseEachProvidersPublishedIDAndBand() {
        let lowToHigh: [ReasoningEffort] = [.low, .medium, .high]
        let lowToMax: [ReasoningEffort] = [.low, .medium, .high, .xhigh, .max]
        let routerBand: [ReasoningEffort] = [.none, .minimal, .low, .medium, .high, .xhigh, .max]

        let openRouter = ModelCatalog.modelInfo(for: "anthropic/claude-haiku-5.5", provider: .openrouter)
        XCTAssertEqual(openRouter.contextWindow, 1_000_000)
        XCTAssertEqual(openRouter.maxOutputTokens, 128_000)
        XCTAssertEqual(openRouter.reasoningConfig?.defaultEffort, .medium)
        XCTAssertEqual(openRouter.reasoningConfig?.supportedEfforts, lowToHigh)
        XCTAssertFalse(openRouter.capabilities.contains(.nativePDF))
        XCTAssertFalse(openRouter.capabilities.contains(.promptCaching))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "anthropic/claude-haiku-5.5", provider: .openrouter))
        XCTAssertFalse(ModelCatalog.seededModels(for: .openrouter).contains(where: { $0.id == "anthropic/claude-haiku-5.5" }))
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .openrouter, modelID: "anthropic/claude-haiku-5.5"))
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: .openrouter, modelID: "anthropic/claude-haiku-5.5")
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(
                for: .openrouter,
                modelID: "anthropic/claude-haiku-5.5",
                declaredEfforts: openRouter.reasoningConfig?.supportedEfforts
            ),
            lowToHigh
        )
        let openRouterBatch = ModelCatalog.modelInfo(for: "anthropic/claude-haiku-5.5:batch", provider: .openrouter)
        XCTAssertEqual(openRouterBatch.contextWindow, 1_000_000)
        XCTAssertEqual(openRouterBatch.maxOutputTokens, 128_000)
        XCTAssertEqual(openRouterBatch.reasoningConfig?.defaultEffort, .medium)
        XCTAssertEqual(openRouterBatch.reasoningConfig?.supportedEfforts, lowToHigh)
        XCTAssertFalse(openRouterBatch.capabilities.contains(.nativePDF))
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "anthropic/claude-haiku-5.5:batch", provider: .openrouter))
        XCTAssertFalse(
            ModelCatalog.seededModels(for: .openrouter).contains(where: { $0.id == "anthropic/claude-haiku-5.5:batch" })
        )
        XCTAssertTrue(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .openrouter, modelID: "anthropic/claude-haiku-5.5:batch")
        )
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "anthropic/claude-haiku-5-5", provider: .openrouter))

        let vercel = ModelCatalog.modelInfo(for: "anthropic/claude-haiku-5.5", provider: .vercelAIGateway)
        XCTAssertEqual(vercel.contextWindow, 1_000_000)
        XCTAssertEqual(vercel.maxOutputTokens, 128_000)
        XCTAssertEqual(vercel.reasoningConfig?.defaultEffort, .medium)
        XCTAssertEqual(vercel.reasoningConfig?.supportedEfforts, lowToMax)
        XCTAssertFalse(vercel.capabilities.contains(.nativePDF))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "anthropic/claude-haiku-5.5", provider: .vercelAIGateway))
        XCTAssertTrue(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .vercelAIGateway, modelID: "anthropic/claude-haiku-5.5")
        )
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(
                for: .vercelAIGateway,
                modelID: "anthropic/claude-haiku-5.5",
                declaredEfforts: vercel.reasoningConfig?.supportedEfforts
            ),
            lowToMax
        )
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "anthropic/claude-haiku-5-5", provider: .vercelAIGateway))

        let databricks = ModelCatalog.modelInfo(for: "databricks-claude-haiku-5-5", provider: .databricks)
        XCTAssertEqual(databricks.contextWindow, 128_000)
        XCTAssertNil(databricks.maxOutputTokens)
        XCTAssertTrue(databricks.capabilities.contains(.vision))
        XCTAssertEqual(databricks.reasoningConfig?.defaultEffort, .medium)
        XCTAssertEqual(databricks.reasoningConfig?.supportedEfforts, lowToHigh)
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "databricks-claude-haiku-5-5", provider: .databricks))
        XCTAssertFalse(ModelCatalog.seededModels(for: .databricks).contains(where: { $0.id == "databricks-claude-haiku-5-5" }))
        XCTAssertTrue(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .databricks, modelID: "databricks-claude-haiku-5-5")
        )

        let router = ModelCatalog.modelInfo(for: "claude-haiku-5-5", provider: .router)
        XCTAssertEqual(router.contextWindow, 1_000_000)
        XCTAssertEqual(router.maxOutputTokens, 128_000)
        XCTAssertEqual(router.reasoningConfig?.defaultEffort, .medium)
        XCTAssertTrue(router.capabilities.contains(.vision))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .router, modelID: "claude-haiku-5-5"),
            routerBand
        )
        XCTAssertFalse(ModelCatalog.isFullySupported(modelID: "claude-haiku-5-5", provider: .router))
        XCTAssertFalse(ModelCatalog.seededModels(for: .router).contains(where: { $0.id == "claude-haiku-5-5" }))
        XCTAssertNil(ModelCatalog.entry(for: "haiku-5-5", provider: .router))
        XCTAssertTrue(ModelSettingsResolver.defaultReasoningCanDisable(for: .router, modelID: "claude-haiku-5-5"))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .router, modelID: "claude-haiku-4-5"),
            [.none, .minimal, .low, .medium, .high, .xhigh]
        )

        XCTAssertNil(ModelCatalog.entry(for: "claude-haiku-5-5", provider: .vertexai))
        XCTAssertNil(ModelCatalog.entry(for: "anthropic/claude-haiku-5.5", provider: .cloudflareAIGateway))
        XCTAssertNil(ModelCatalog.entry(for: "anthropic/claude-haiku-5-5", provider: .deepinfra))
        XCTAssertNil(ModelCatalog.entry(for: "claude-haiku-5-5", provider: .githubCopilot))
    }
}
