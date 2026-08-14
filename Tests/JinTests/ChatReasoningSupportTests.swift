import XCTest
@testable import Jin

final class ChatReasoningSupportTests: XCTestCase {
    func testReasoningHelpTextMatchesProviderCopy() {
        XCTAssertEqual(
            ChatReasoningSupport.reasoningHelpText(
                supportsReasoningControl: false,
                providerType: .anthropic,
                label: "High"
            ),
            "Reasoning: Not supported"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningHelpText(
                supportsReasoningControl: true,
                providerType: .anthropic,
                label: "High"
            ),
            "Thinking: High"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningHelpText(
                supportsReasoningControl: true,
                providerType: .gemini,
                label: "On"
            ),
            "Thinking: On"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningHelpText(
                supportsReasoningControl: true,
                providerType: .openai,
                label: "Medium"
            ),
            "Reasoning: Medium"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningHelpText(
                supportsReasoningControl: true,
                providerType: nil,
                label: "On"
            ),
            "Reasoning: On"
        )
    }

    func testReasoningBadgeTextMatchesConfigAndControlState() {
        XCTAssertNil(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: false,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))
            )
        )
        XCTAssertNil(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: false,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: false, effort: .high))
            )
        )
        XCTAssertNil(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .none),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true))
            )
        )

        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .budget),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, budgetTokens: 1024))
            ),
            "1024"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .budget),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, budgetTokens: 4096))
            ),
            "4096"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .budget),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, budgetTokens: 10_000))
            ),
            "10K"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .budget),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, budgetTokens: 8000))
            ),
            "8K"
        )

        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .minimal))
            ),
            "Min"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .low))
            ),
            "Low"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .medium))
            ),
            "Med"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .high))
            ),
            "High"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh))
            ),
            "Ext"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .max))
            ),
            "Max"
        )
        XCTAssertNil(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: ReasoningEffort.none))
            )
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .effort),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true))
            ),
            "On"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .toggle),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true))
            ),
            "On"
        )
    }

    func testNormalizeReasoningControlsClearsUnsupportedReasoning() {
        var controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                effort: .high,
                budgetTokens: 1024,
                summary: .auto
            )
        )

        ChatReasoningSupport.normalizeReasoningControls(
            controls: &controls,
            supportsReasoningControl: false,
            selectedReasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            providerType: .openai,
            modelID: "gpt-5",
            supportsReasoningSummaryControl: true,
            reasoningMustRemainEnabled: false,
            defaultAnthropicEffort: .high,
            defaultAnthropicBudget: 1024
        )

        XCTAssertNil(controls.reasoning)
    }

    func testNormalizeReasoningControlsDefaultsEffortAndSummaryForEnabledEffortModels() {
        var controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                budgetTokens: 4096
            )
        )

        ChatReasoningSupport.normalizeReasoningControls(
            controls: &controls,
            supportsReasoningControl: true,
            selectedReasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
            providerType: .openai,
            modelID: "gpt-5",
            supportsReasoningSummaryControl: true,
            reasoningMustRemainEnabled: false,
            defaultAnthropicEffort: .high,
            defaultAnthropicBudget: 1024
        )

        XCTAssertEqual(controls.reasoning?.enabled, true)
        XCTAssertEqual(controls.reasoning?.effort, .high)
        XCTAssertNil(controls.reasoning?.budgetTokens)
        XCTAssertEqual(controls.reasoning?.summary, .auto)
    }

    func testNormalizeReasoningControlsDefaultsBudgetAndClearsEffortState() {
        var controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                effort: .high,
                summary: .auto
            )
        )

        ChatReasoningSupport.normalizeReasoningControls(
            controls: &controls,
            supportsReasoningControl: true,
            selectedReasoningConfig: ModelReasoningConfig(type: .budget, defaultBudget: 10_000),
            providerType: .openai,
            modelID: "o3",
            supportsReasoningSummaryControl: true,
            reasoningMustRemainEnabled: false,
            defaultAnthropicEffort: .high,
            defaultAnthropicBudget: 1024
        )

        XCTAssertEqual(controls.reasoning?.enabled, true)
        XCTAssertNil(controls.reasoning?.effort)
        XCTAssertEqual(controls.reasoning?.budgetTokens, 10_000)
        XCTAssertNil(controls.reasoning?.summary)
    }

    func testNormalizeReasoningControlsCreatesToggleReasoningAndClearsDetailedState() {
        var controls = GenerationControls()

        ChatReasoningSupport.normalizeReasoningControls(
            controls: &controls,
            supportsReasoningControl: true,
            selectedReasoningConfig: ModelReasoningConfig(type: .toggle),
            providerType: .deepseek,
            modelID: "deepseek-reasoner",
            supportsReasoningSummaryControl: false,
            reasoningMustRemainEnabled: false,
            defaultAnthropicEffort: .high,
            defaultAnthropicBudget: 1024
        )

        XCTAssertEqual(controls.reasoning?.enabled, true)
        XCTAssertNil(controls.reasoning?.effort)
        XCTAssertNil(controls.reasoning?.budgetTokens)
        XCTAssertNil(controls.reasoning?.summary)
    }

    func testNormalizeReasoningControlsKeepsRequiredReasoningEnabled() {
        var controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: false,
                effort: ReasoningEffort.none
            )
        )

        ChatReasoningSupport.normalizeReasoningControls(
            controls: &controls,
            supportsReasoningControl: true,
            selectedReasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
            providerType: .openai,
            modelID: "gpt-5",
            supportsReasoningSummaryControl: true,
            reasoningMustRemainEnabled: true,
            defaultAnthropicEffort: .high,
            defaultAnthropicBudget: 1024
        )

        XCTAssertEqual(controls.reasoning?.enabled, true)
        XCTAssertEqual(controls.reasoning?.effort, .medium)
    }

    func testNormalizeReasoningEffortLimitsClampsUnsupportedEffort() {
        var controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                effort: .medium
            )
        )

        ChatReasoningSupport.normalizeReasoningEffortLimits(
            controls: &controls,
            supportsReasoningControl: true,
            providerType: .mistral,
            modelID: "mistral-medium-3.5",
            defaultAnthropicEffort: .high,
            defaultAnthropicBudget: 1024
        )

        XCTAssertEqual(controls.reasoning?.effort, .high)
    }

    func testApplyThinkingBudgetDraftPreservesAnthropicDisplaySelectionWhenMaxTokensDraftIsNil() {
        var controls = GenerationControls(
            reasoning: ReasoningControls(
                enabled: true,
                effort: .xhigh,
                anthropicThinkingDisplay: .summarized
            )
        )

        let resolvedMaxTokensDraft = ChatReasoningSupport.applyThinkingBudgetDraft(
            controls: &controls,
            providerType: .anthropic,
            modelID: "claude-opus-4-7",
            anthropicUsesAdaptiveThinking: true,
            anthropicUsesEffortMode: true,
            anthropicThinkingDisplay: .omitted,
            budgetTokens: nil,
            maxTokens: nil,
            defaultEffort: .high,
            defaultBudget: 1024
        )

        XCTAssertEqual(controls.reasoning?.anthropicThinkingDisplay, .omitted)
        XCTAssertEqual(controls.maxTokens, 128_000)
        XCTAssertEqual(resolvedMaxTokensDraft, "128000")
    }

    func testFireworksReasoningHistoryProviderSpecificMutatorSetsAndClearsValue() {
        var controls = GenerationControls()

        controls = ChatReasoningSupport.setFireworksReasoningHistory(
            "interleaved",
            controls: controls
        )

        XCTAssertEqual(ChatReasoningSupport.fireworksReasoningHistory(controls: controls), "interleaved")
        XCTAssertEqual(controls.providerSpecific["reasoning_history"]?.value as? String, "interleaved")

        controls = ChatReasoningSupport.setFireworksReasoningHistory(nil, controls: controls)

        XCTAssertNil(ChatReasoningSupport.fireworksReasoningHistory(controls: controls))
        XCTAssertNil(controls.providerSpecific["reasoning_history"])
    }

    func testCerebrasPreserveThinkingMapsToClearThinkingProviderSpecificDefault() {
        var controls = GenerationControls()

        XCTAssertFalse(ChatReasoningSupport.cerebrasPreservesThinking(controls: controls))

        controls = ChatReasoningSupport.setCerebrasPreservesThinking(true, controls: controls)

        XCTAssertTrue(ChatReasoningSupport.cerebrasPreservesThinking(controls: controls))
        XCTAssertEqual(controls.providerSpecific["clear_thinking"]?.value as? Bool, false)

        controls = ChatReasoningSupport.setCerebrasPreservesThinking(false, controls: controls)

        XCTAssertFalse(ChatReasoningSupport.cerebrasPreservesThinking(controls: controls))
        XCTAssertNil(controls.providerSpecific["clear_thinking"])
    }

    func testEffortLevelsForReasoningMenuDropsNoneWhenDisableToggleIsShown() {
        // Kimi K3 / Inkling-style bands include `.none` ("Off") as a wire effort.
        // The composer also renders a dedicated Off toggle — keep only one "Off".
        let kimiK3Band: [ReasoningEffort] = [.none, .low, .high, .max]
        XCTAssertEqual(
            ChatReasoningSupport.effortLevelsForReasoningMenu(
                supported: kimiK3Band,
                includesDisableToggle: true
            ),
            [.low, .high, .max]
        )
        XCTAssertEqual(
            ChatReasoningSupport.effortLevelsForReasoningMenu(
                supported: kimiK3Band,
                includesDisableToggle: false
            ),
            kimiK3Band
        )

        let fullBand: [ReasoningEffort] = [.none, .minimal, .low, .medium, .high, .xhigh, .max]
        XCTAssertEqual(
            ChatReasoningSupport.effortLevelsForReasoningMenu(
                supported: fullBand,
                includesDisableToggle: true
            ),
            [.minimal, .low, .medium, .high, .xhigh, .max]
        )

        // Models without a `.none` effort keep the full list either way.
        let openAIBand: [ReasoningEffort] = [.low, .medium, .high]
        XCTAssertEqual(
            ChatReasoningSupport.effortLevelsForReasoningMenu(
                supported: openAIBand,
                includesDisableToggle: true
            ),
            openAIBand
        )
    }

    func testReasoningOffMenuSelectionTreatsNoneEffortAsOffWhenToggleOwnsLabel() {
        XCTAssertTrue(
            ChatReasoningSupport.isReasoningOffMenuSelected(
                isReasoningEnabled: false,
                currentEffort: .high,
                includesDisableToggle: true
            )
        )
        // Qualify `ReasoningEffort.none` — bare `.none` is Optional.none (nil)
        // for a `ReasoningEffort?` parameter and would never match the effort.
        XCTAssertTrue(
            ChatReasoningSupport.isReasoningOffMenuSelected(
                isReasoningEnabled: true,
                currentEffort: ReasoningEffort.none,
                includesDisableToggle: true
            )
        )
        XCTAssertFalse(
            ChatReasoningSupport.isReasoningOffMenuSelected(
                isReasoningEnabled: true,
                currentEffort: .high,
                includesDisableToggle: true
            )
        )
        // Without the dedicated toggle, effort.none is a normal effort row — Off is not
        // separately selected via the disable control.
        XCTAssertFalse(
            ChatReasoningSupport.isReasoningOffMenuSelected(
                isReasoningEnabled: true,
                currentEffort: ReasoningEffort.none,
                includesDisableToggle: false
            )
        )
    }

    func testKimiK3SupportedEffortsStillIncludeNoneForAPIAndModelSettings() {
        // Registry keeps `.none` for adapters / default-effort pickers; only the menu
        // presentation layer dedupes the Off label.
        for (provider, modelID) in [
            (ProviderType.baseten, "moonshotai/Kimi-K3"),
            (.modal, "moonshotai/Kimi-K3"),
            (.fireworks, "accounts/fireworks/models/kimi-k3")
        ] {
            let efforts = ModelCapabilityRegistry.supportedReasoningEfforts(
                for: provider,
                modelID: modelID
            )
            XCTAssertTrue(
                efforts.contains(.none),
                "\(provider.rawValue)/\(modelID) should keep .none in supported efforts"
            )
            XCTAssertEqual(
                ChatReasoningSupport.effortLevelsForReasoningMenu(
                    supported: efforts,
                    includesDisableToggle: true
                ).filter { $0 == .none },
                [],
                "Composer menu must not list .none beside the Off toggle for \(provider.rawValue)"
            )
        }
    }
}
