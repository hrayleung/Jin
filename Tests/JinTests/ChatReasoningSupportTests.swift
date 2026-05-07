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
            "L"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .budget),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, budgetTokens: 4096))
            ),
            "H"
        )
        XCTAssertEqual(
            ChatReasoningSupport.reasoningBadgeText(
                supportsReasoningControl: true,
                isReasoningEnabled: true,
                selectedReasoningConfig: ModelReasoningConfig(type: .budget),
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, budgetTokens: 10_000))
            ),
            "On"
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
                controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh))
            ),
            "X"
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
}
