import Foundation
import XCTest
@testable import Jin

/// Claude Opus 5 support.
///
/// Opus 5 inherits Opus 4.8's request surface (adaptive thinking only, no `budget_tokens`,
/// no sampling params, 1M context / 128k output, full `low`…`max` effort ladder) with two
/// behavioural flips that are easy to miss:
///
/// 1. Thinking is ON when `thinking` is omitted (Opus 4.8 ran without thinking), so
///    disabling reasoning requires an explicit `{type: "disabled"}`.
/// 2. That explicit disable is only accepted at effort `high` or below — pairing it with
///    `xhigh`/`max` returns a 400.
final class AnthropicOpus5SupportTests: XCTestCase {

    // MARK: - Catalog

    func testOpus5CatalogRecordIsSeededWithVerifiedLimits() throws {
        let opus5 = try XCTUnwrap(
            ModelCatalog.seededModels(for: .anthropic).first(where: { $0.id == "claude-opus-5" }),
            "Opus 5 must be seeded so it appears in the picker on first launch"
        )

        XCTAssertEqual(opus5.name, "Claude Opus 5")
        XCTAssertEqual(opus5.contextWindow, 1_000_000)
        XCTAssertEqual(opus5.maxOutputTokens, 128_000)
        XCTAssertEqual(opus5.reasoningConfig?.type, .effort)
        XCTAssertEqual(opus5.reasoningConfig?.defaultEffort, .high)
        XCTAssertTrue(opus5.capabilities.contains(.nativePDF))
        XCTAssertTrue(opus5.capabilities.contains(.codeExecution))
        XCTAssertTrue(opus5.capabilities.contains(.promptCaching))
        XCTAssertTrue(opus5.capabilities.contains(.vision))
    }

    func testOpus5LeadsTheAnthropicPreferenceLadder() {
        // The ladder drives both the picker default and the fallback a fresh conversation
        // lands on, so it has to move with the flagship.
        XCTAssertEqual(ChatModelSelectionSupport.preferredAnthropicModelOrder.first, "claude-opus-5")
    }

    func testOpus5IsAvailableOnEveryGatewayThatServesIt() {
        // Live-verified 2026-07-25 against each gateway's own catalog endpoint / docs.
        // `entry(for:provider:)` is the optional lookup — `modelInfo(for:provider:)`
        // synthesizes a record for unknown IDs and would pass vacuously.
        XCTAssertNotNil(ModelCatalog.entry(for: "anthropic/claude-opus-5", provider: .openrouter))
        XCTAssertNotNil(ModelCatalog.entry(for: "anthropic/claude-opus-5-fast", provider: .openrouter))
        XCTAssertNotNil(ModelCatalog.entry(for: "anthropic/claude-opus-5", provider: .vercelAIGateway))
        XCTAssertNotNil(ModelCatalog.entry(for: "anthropic/claude-opus-5", provider: .cloudflareAIGateway))
        XCTAssertNotNil(ModelCatalog.entry(for: "databricks-claude-opus-5", provider: .databricks))

        // Claude Managed Agents reuses the direct-Anthropic records, so Opus 5 must be
        // selectable there too.
        XCTAssertNotNil(ModelCatalog.entry(for: "claude-opus-5", provider: .claudeManagedAgents))
    }

    // MARK: - Request-shape limits

    func testOpus5UsesAdaptiveThinkingAndFullEffortLadder() {
        XCTAssertTrue(AnthropicModelLimits.supportsAdaptiveThinking(for: "claude-opus-5"))
        XCTAssertTrue(AnthropicModelLimits.supportsEffort(for: "claude-opus-5"))
        XCTAssertTrue(AnthropicModelLimits.supportsXHighEffort(for: "claude-opus-5"))
        XCTAssertTrue(AnthropicModelLimits.supportsMaxEffort(for: "claude-opus-5"))
        XCTAssertEqual(AnthropicModelLimits.maxOutputTokens(for: "claude-opus-5"), 128_000)

        XCTAssertEqual(
            ModelCapabilityRegistry.supportedReasoningEfforts(for: .anthropic, modelID: "claude-opus-5"),
            [.low, .medium, .high, .xhigh, .max]
        )
    }

    func testOpus5KeepsTheFullEffortLadderOnOpenRouter() {
        // OpenRouter reports supported_efforts = [max, xhigh, high, medium, low] for both
        // Opus 5 variants (live-verified 2026-07-25). Without an explicit band they fall
        // through to the low/medium/high default, which silently clamps xhigh/max to high.
        for id in ["anthropic/claude-opus-5", "anthropic/claude-opus-5-fast"] {
            XCTAssertEqual(
                ModelCapabilityRegistry.supportedReasoningEfforts(for: .openrouter, modelID: id),
                [.low, .medium, .high, .xhigh, .max],
                "\(id) must offer the full ladder OpenRouter accepts"
            )
            XCTAssertEqual(
                ModelCapabilityRegistry.normalizedReasoningEffort(.max, for: .openrouter, modelID: id),
                .max,
                "\(id) must not fold max down to high"
            )
            XCTAssertEqual(
                ModelCapabilityRegistry.normalizedReasoningEffort(.xhigh, for: .openrouter, modelID: id),
                .xhigh,
                "\(id) must not fold xhigh down to high"
            )
        }
    }

    func testOpus5RejectsSamplingParametersAndDefaultsThinkingDisplayToSummarized() {
        XCTAssertFalse(AnthropicModelLimits.supportsSamplingParameters(for: "claude-opus-5"))
        XCTAssertTrue(AnthropicModelLimits.requiresExplicitThinkingDisplay(for: "claude-opus-5"))
    }

    func testOpus5RequiresExplicitThinkingDisabledUnlikeOpus48() {
        // The flip: omitting `thinking` runs adaptive on Opus 5, but ran without thinking
        // on Opus 4.8 — so only Opus 5 needs the explicit disable block.
        XCTAssertTrue(AnthropicModelLimits.requiresExplicitThinkingDisabled(for: "claude-opus-5"))
        XCTAssertFalse(AnthropicModelLimits.requiresExplicitThinkingDisabled(for: "claude-opus-4-8"))
        XCTAssertFalse(AnthropicModelLimits.requiresExplicitThinkingDisabled(for: "claude-sonnet-5"))
    }

    func testOpus5SupportsCodeExecutionAndWebSearchDynamicFiltering() {
        XCTAssertTrue(ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: "claude-opus-5"))
        XCTAssertTrue(ModelCapabilityRegistry.supportsWebSearch(for: .anthropic, modelID: "claude-opus-5"))
        XCTAssertTrue(
            ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(for: .anthropic, modelID: "claude-opus-5")
        )
    }

    // MARK: - Thinking body

    func testApplyThinkingConfigForOpus5UsesAdaptiveAndSummarizedDisplay() throws {
        var body: [String: Any] = [:]

        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: GenerationControls(
                temperature: 0.4,
                topP: 0.8,
                reasoning: ReasoningControls(enabled: true, effort: .max)
            ),
            providerType: .anthropic,
            modelID: "claude-opus-5"
        )

        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "adaptive")
        XCTAssertEqual(thinking["display"] as? String, "summarized")
        XCTAssertNil(thinking["budget_tokens"], "budget_tokens is removed on Opus 5 and 400s")

        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "max")

        XCTAssertNil(body["temperature"], "Opus 5 does not accept sampling params")
        XCTAssertNil(body["top_p"], "Opus 5 does not accept sampling params")
    }

    func testApplyThinkingConfigForOpus5DisabledSendsExplicitDisabledTypeWithoutEffort() throws {
        var body: [String: Any] = [:]

        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: GenerationControls(
                reasoning: ReasoningControls(enabled: false, effort: .max)
            ),
            providerType: .anthropic,
            modelID: "claude-opus-5"
        )

        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "disabled")
        // No effort is emitted on the disabled path, so the API default (`high`) applies —
        // which is exactly what the disabled block is allowed to pair with.
        XCTAssertNil(body["output_config"])
    }

    func testApplyThinkingConfigForOpus5OmitsThinkingWhenNoPreferenceWasEverSet() {
        var body: [String: Any] = [:]

        // `reasoning == nil` means the user never expressed a preference — leave `thinking`
        // omitted so Opus 5 runs its own adaptive-on default rather than being forced off.
        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: GenerationControls(),
            providerType: .anthropic,
            modelID: "claude-opus-5"
        )

        XCTAssertNil(body["thinking"])
    }

    // MARK: - Disabled-thinking effort cap

    func testNormalizeDisabledThinkingEffortClampsXHighAndMaxOnOpus5() {
        for effort in ["xhigh", "max"] {
            var body: [String: Any] = [
                "thinking": ["type": "disabled"],
                "output_config": ["effort": effort]
            ]

            AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &body, modelID: "claude-opus-5")

            let outputConfig = body["output_config"] as? [String: Any]
            XCTAssertEqual(
                outputConfig?["effort"] as? String,
                "high",
                "Opus 5 400s when a disabled thinking block is paired with effort \(effort)"
            )
        }
    }

    func testNormalizeDisabledThinkingEffortClampsAnyCodableWrappedOverrides() {
        // Provider-specific overrides arrive as AnyCodable-wrapped values, which is the
        // path that can actually smuggle an xhigh/max effort past the disabled branch.
        var body: [String: Any] = [
            "thinking": ["type": AnyCodable("disabled")],
            "output_config": ["effort": AnyCodable("xhigh")]
        ]

        AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &body, modelID: "claude-opus-5")

        let outputConfig = body["output_config"] as? [String: Any]
        XCTAssertEqual(outputConfig?["effort"] as? String, "high")
    }

    func testNormalizeDisabledThinkingEffortLeavesAllowedCombinationsAlone() {
        var body: [String: Any] = [
            "thinking": ["type": "disabled"],
            "output_config": ["effort": "medium"]
        ]

        AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &body, modelID: "claude-opus-5")

        let outputConfig = body["output_config"] as? [String: Any]
        XCTAssertEqual(outputConfig?["effort"] as? String, "medium")
    }

    func testNormalizeDisabledThinkingEffortLeavesAdaptiveThinkingAlone() {
        var body: [String: Any] = [
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "max"]
        ]

        AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &body, modelID: "claude-opus-5")

        let outputConfig = body["output_config"] as? [String: Any]
        XCTAssertEqual(outputConfig?["effort"] as? String, "max", "The cap only applies with thinking OFF")
    }

    func testNormalizeDisabledThinkingEffortDoesNotApplyToOtherModels() {
        var body: [String: Any] = [
            "thinking": ["type": "disabled"],
            "output_config": ["effort": "max"]
        ]

        AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &body, modelID: "claude-sonnet-5")

        let outputConfig = body["output_config"] as? [String: Any]
        XCTAssertEqual(outputConfig?["effort"] as? String, "max")
        XCTAssertFalse(AnthropicModelLimits.disabledThinkingRequiresEffortAtMostHigh(for: "claude-sonnet-5"))
    }
}
