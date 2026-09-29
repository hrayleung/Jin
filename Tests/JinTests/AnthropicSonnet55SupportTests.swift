import XCTest
@testable import Jin

/// Claude Sonnet 5.5 (`claude-sonnet-5-5`, released 2026-09-28) matches the
/// `claude-sonnet-5` family prefix, so it inherits Sonnet 5's always-on adaptive
/// thinking surface (never `disabled`, never `budget_tokens`, no sampling params,
/// summarized display, full low…max ladder). Its own model page adds the exact
/// facts pinned here: 1M / 128K, default effort `high`, code execution and dynamic
/// web-search filtering, no fast mode.
final class AnthropicSonnet55SupportTests: XCTestCase {

    func testSonnet55CatalogRecordIsSeededAheadOfSonnet5WithVerifiedLimits() throws {
        let seeded = ModelCatalog.seededModels(for: .anthropic)
        let sonnet55 = try XCTUnwrap(
            seeded.first(where: { $0.id == "claude-sonnet-5-5" }),
            "Sonnet 5.5 must be seeded so it appears in the picker on first launch"
        )

        XCTAssertEqual(sonnet55.name, "Claude Sonnet 5.5")
        XCTAssertEqual(sonnet55.contextWindow, 1_000_000)
        XCTAssertEqual(sonnet55.maxOutputTokens, 128_000)
        XCTAssertEqual(sonnet55.reasoningConfig?.type, .effort)
        XCTAssertEqual(sonnet55.reasoningConfig?.defaultEffort, .high)
        for capability: ModelCapability in [
            .streaming, .toolCalling, .vision, .reasoning, .promptCaching, .nativePDF, .codeExecution,
        ] {
            XCTAssertTrue(sonnet55.capabilities.contains(capability), "\(capability)")
        }
        // Input is text + images only — no audio/video is documented.
        XCTAssertFalse(sonnet55.capabilities.contains(.videoInput))
        XCTAssertFalse(sonnet55.capabilities.contains(.audio))

        let ids = seeded.map(\.id)
        let index55 = try XCTUnwrap(ids.firstIndex(of: "claude-sonnet-5-5"))
        let index5 = try XCTUnwrap(ids.firstIndex(of: "claude-sonnet-5"))
        XCTAssertLessThan(index55, index5, "newest Sonnet leads its tier in the picker")
    }

    func testSonnet55IsFullySupportedOnAnthropicAndManagedAgentsButNearMissesAreNot() {
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "claude-sonnet-5-5", provider: .anthropic))
        XCTAssertTrue(ModelCatalog.isFullySupported(modelID: "claude-sonnet-5-5", provider: .claudeManagedAgents))
        XCTAssertTrue(JinModelSupport.supportsNativePDF(providerType: .anthropic, modelID: "claude-sonnet-5-5"))
        XCTAssertTrue(
            ChatModelCapabilitySupport.adapterCanSendNativePDF(
                providerType: .anthropic,
                modelID: "claude-sonnet-5-5"
            )
        )
        for id in ["claude-sonnet-5-6", "claude-sonnet-5-5-custom", "claude-sonnet-55", "claude-sonnet-5.5"] {
            XCTAssertFalse(ModelCatalog.isFullySupported(modelID: id, provider: .anthropic), id)
        }
    }

    func testSonnet55LeadsSonnet5InThePreferredModelOrder() throws {
        let order = ChatModelSelectionSupport.preferredAnthropicModelOrder
        let index55 = try XCTUnwrap(order.firstIndex(of: "claude-sonnet-5-5"))
        let index5 = try XCTUnwrap(order.firstIndex(of: "claude-sonnet-5"))
        XCTAssertLessThan(index55, index5)
    }

    func testSonnet55CannotDisableThinking() {
        // `{type:"disabled"}` and `budget_tokens` both return 400 (its what's-new points at
        // `between_tools`, which Jin does not surface), so every escape hatch stays shut.
        XCTAssertTrue(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-sonnet-5-5"))
        XCTAssertFalse(AnthropicModelLimits.requiresExplicitThinkingDisabled(for: "claude-sonnet-5-5"))
        XCTAssertFalse(AnthropicModelLimits.disabledThinkingRequiresEffortAtMostHigh(for: "claude-sonnet-5-5"))
        XCTAssertFalse(ModelSettingsResolver.defaultReasoningCanDisable(for: .anthropic, modelID: "claude-sonnet-5-5"))
        XCTAssertFalse(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .claudeManagedAgents, modelID: "claude-sonnet-5-5")
        )
        // A custom suffix is not the documented ID and keeps the toggleable default.
        XCTAssertTrue(
            ModelSettingsResolver.defaultReasoningCanDisable(for: .anthropic, modelID: "claude-sonnet-5-5-custom")
        )
    }

    func testSonnet55ApiSurfaceMatchesTheSonnet5Family() {
        XCTAssertFalse(AnthropicModelLimits.supportsSamplingParameters(for: "claude-sonnet-5-5"))
        XCTAssertTrue(AnthropicModelLimits.requiresExplicitThinkingDisplay(for: "claude-sonnet-5-5"))
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-sonnet-5-5"), 128_000)
        XCTAssertTrue(AnthropicModelLimits.supportsXHighEffort(for: "claude-sonnet-5-5"))
        XCTAssertTrue(AnthropicModelLimits.supportsMaxEffort(for: "claude-sonnet-5-5"))
        // Fast mode is documented for Opus 5.5 / 5 / 4.8 only; Sonnet 5.5's page lists it as unsupported.
        XCTAssertFalse(AnthropicModelLimits.supportsFastMode(for: "claude-sonnet-5-5"))
        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: "claude-sonnet-5-5"),
            [.low, .medium, .high, .xhigh, .max]
        )
    }

    func testSonnet55ServerToolsFollowTheDocumentedLists() {
        // Code-execution tool page `supportedModels` names both 5.5 models (re-read 2026-09-29).
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-5-5"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-5-5"))
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-sonnet-5-5-custom")
        )
        // Web search: "dynamic filtering is available with Claude 4.6 and later models".
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: "claude-sonnet-5-5"))
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: "claude-sonnet-5-5")
        )
        XCTAssertFalse(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: "claude-sonnet-5-5-custom")
        )
    }

    func testOpus55RecordClaimsCodeExecutionFromTheToolPage() {
        let opus55 = ModelCatalog.modelInfo(for: "claude-opus-5-5", provider: .anthropic)
        XCTAssertTrue(opus55.capabilities.contains(.codeExecution))
    }

    func testApplyThinkingConfigForSonnet55DisabledOmitsThinkingAndSampling() {
        var body: [String: Any] = [:]

        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: GenerationControls(
                temperature: 0.4,
                topP: 0.8,
                reasoning: ReasoningControls(enabled: false)
            ),
            providerType: .anthropic,
            modelID: "claude-sonnet-5-5"
        )

        XCTAssertNil(body["thinking"], "Sonnet 5.5 400s on {type: disabled} — omit the field")
        XCTAssertNil(body["temperature"], "non-default sampling params 400 on Sonnet 5.5")
        XCTAssertNil(body["top_p"], "non-default sampling params 400 on Sonnet 5.5")
    }

    func testApplyThinkingConfigForSonnet55UsesAdaptiveSummarizedWithFullEffortLadder() throws {
        for (effort, wire) in [(ReasoningEffort.xhigh, "xhigh"), (.max, "max"), (.low, "low")] {
            var body: [String: Any] = [:]

            AnthropicRequestBodySupport.applyThinkingConfig(
                to: &body,
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: effort)),
                providerType: .anthropic,
                modelID: "claude-sonnet-5-5"
            )

            let thinking = try XCTUnwrap(body["thinking"] as? [String: Any], wire)
            XCTAssertEqual(thinking["type"] as? String, "adaptive", wire)
            // `display` defaults to "omitted" on 5.5 — Jin opts in so summaries and progress
            // updates are readable.
            XCTAssertEqual(thinking["display"] as? String, "summarized", wire)
            XCTAssertNil(thinking["budget_tokens"], wire)

            let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any], wire)
            XCTAssertEqual(outputConfig["effort"] as? String, wire)
        }
    }

    /// A row persisted before the catalog knew the ID (Fetch / Add Model → unknown-model defaults)
    /// must pick up the exact catalog record when resolved — nothing stored may pin stale numbers.
    func testLegacyPersistedSonnet55RowResolvesToCatalogSpecs() {
        let legacy = ModelInfo(
            id: "claude-sonnet-5-5",
            name: "claude-sonnet-5-5",
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
            XCTAssertEqual(resolved.reasoningConfig?.defaultEffort, .high, "\(providerType)")
            XCTAssertFalse(resolved.reasoningCanDisable, "\(providerType)")
        }
        XCTAssertTrue(ModelSettingsResolver.resolve(model: legacy, providerType: .anthropic).supportsWebSearch)
    }

    func testSonnet55ProviderSpecificBudgetOverrideNormalizesToAdaptive() throws {
        var body: [String: Any] = [:]
        var controls = GenerationControls(
            reasoning: ReasoningControls(enabled: true, effort: .high, budgetTokens: 4096)
        )
        controls.providerSpecific["thinking"] = AnyCodable([
            "type": "enabled",
            "budget_tokens": 4096,
        ] as [String: Any])

        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: controls,
            providerType: .anthropic,
            modelID: "claude-sonnet-5-5"
        )
        AnthropicRequestBodySupport.applyProviderSpecificOverrides(
            to: &body,
            controls: controls,
            modelID: "claude-sonnet-5-5",
            supportsDynamicFiltering: true
        )
        AnthropicRequestBodySupport.sanitizeAdaptiveThinking(in: &body, modelID: "claude-sonnet-5-5")

        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "adaptive")
        XCTAssertNil(thinking["budget_tokens"])
    }
}
