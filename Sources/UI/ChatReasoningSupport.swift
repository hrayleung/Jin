import Foundation

enum ChatReasoningSupport {
    static func anthropicUsesAdaptiveThinking(providerType: ProviderType?, modelID: String) -> Bool {
        guard providerType == .anthropic else { return false }
        return AnthropicModelLimits.supportsAdaptiveThinking(for: modelID)
    }

    static func anthropicUsesEffortMode(providerType: ProviderType?, modelID: String) -> Bool {
        guard providerType == .anthropic else { return false }
        return AnthropicModelLimits.supportsEffort(for: modelID)
    }

    static func updateReasoning(
        controls: inout GenerationControls,
        mutate: (inout ReasoningControls) -> Void
    ) {
        var reasoning = controls.reasoning ?? ReasoningControls(enabled: false)
        mutate(&reasoning)
        controls.reasoning = reasoning
    }

    static func normalizeAnthropicReasoningAndMaxTokens(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        modelID: String,
        defaultEffort: ReasoningEffort,
        defaultBudget: Int
    ) {
        guard providerType == .anthropic else { return }
        guard var reasoning = controls.reasoning else { return }

        var maxTokens = controls.maxTokens
        AnthropicReasoningNormalizer.normalize(
            reasoning: &reasoning,
            maxTokens: &maxTokens,
            modelID: modelID,
            defaults: .init(
                effort: defaultEffort,
                budgetTokens: defaultBudget
            )
        )
        controls.reasoning = reasoning
        controls.maxTokens = maxTokens
    }

    static func setReasoningOff(
        controls: inout GenerationControls,
        reasoningMustRemainEnabled: Bool,
        selectedReasoningConfig: ModelReasoningConfig?,
        providerType: ProviderType?,
        modelID: String,
        defaultBudget: Int
    ) {
        if reasoningMustRemainEnabled {
            updateReasoning(controls: &controls) { reasoning in
                reasoning.enabled = true
                if selectedReasoningConfig?.type == .effort,
                   reasoning.effort == nil || reasoning.effort == ReasoningEffort.none {
                    reasoning.effort = selectedReasoningConfig?.defaultEffort ?? .medium
                }
            }
            return
        }

        updateReasoning(controls: &controls) { reasoning in
            reasoning.enabled = false
        }
        normalizeAnthropicReasoningAndMaxTokens(
            controls: &controls,
            providerType: providerType,
            modelID: modelID,
            defaultEffort: selectedReasoningConfig?.defaultEffort ?? .high,
            defaultBudget: defaultBudget
        )
    }

    static func setReasoningOn(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        modelID: String,
        defaultEffort: ReasoningEffort,
        defaultBudget: Int
    ) {
        updateReasoning(controls: &controls) { reasoning in
            reasoning.enabled = true
        }
        normalizeAnthropicReasoningAndMaxTokens(
            controls: &controls,
            providerType: providerType,
            modelID: modelID,
            defaultEffort: defaultEffort,
            defaultBudget: defaultBudget
        )
    }

    static func setReasoningEffort(
        controls: inout GenerationControls,
        effort: ReasoningEffort,
        supportsReasoningSummaryControl: Bool
    ) {
        updateReasoning(controls: &controls) { reasoning in
            reasoning.enabled = true
            reasoning.effort = effort
            reasoning.budgetTokens = nil
            if supportsReasoningSummaryControl, reasoning.summary == nil {
                reasoning.summary = .auto
            }
        }
    }

    static func setAnthropicThinkingBudget(
        controls: inout GenerationControls,
        budgetTokens: Int,
        providerType: ProviderType?,
        modelID: String,
        defaultEffort: ReasoningEffort,
        defaultBudget: Int
    ) {
        updateReasoning(controls: &controls) { reasoning in
            reasoning.enabled = true
            reasoning.effort = nil
            reasoning.budgetTokens = budgetTokens
            reasoning.summary = nil
        }
        normalizeAnthropicReasoningAndMaxTokens(
            controls: &controls,
            providerType: providerType,
            modelID: modelID,
            defaultEffort: defaultEffort,
            defaultBudget: defaultBudget
        )
    }

    static func normalizedAnthropicEffort(
        currentEffort: ReasoningEffort?,
        defaultEffort: ReasoningEffort
    ) -> ReasoningEffort {
        let value = currentEffort ?? defaultEffort
        switch value {
        case .none, .minimal:
            return .low
        case .low, .medium, .high, .xhigh:
            return value
        }
    }

    static func setAnthropicEffort(
        controls: inout GenerationControls,
        newValue: ReasoningEffort,
        anthropicUsesAdaptiveThinking: Bool,
        modelID: String,
        defaultEffort: ReasoningEffort,
        defaultBudget: Int
    ) {
        updateReasoning(controls: &controls) { reasoning in
            reasoning.enabled = true
            reasoning.effort = newValue
            reasoning.summary = nil
            if anthropicUsesAdaptiveThinking {
                reasoning.budgetTokens = nil
            }
        }
        normalizeAnthropicReasoningAndMaxTokens(
            controls: &controls,
            providerType: .anthropic,
            modelID: modelID,
            defaultEffort: defaultEffort,
            defaultBudget: defaultBudget
        )
    }

    static func applyThinkingBudgetDraft(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        modelID: String,
        anthropicUsesAdaptiveThinking: Bool,
        anthropicUsesEffortMode: Bool,
        budgetTokens: Int?,
        maxTokens: Int?,
        defaultEffort: ReasoningEffort,
        defaultBudget: Int
    ) -> String? {
        guard providerType != .anthropic || maxTokens != nil else { return nil }

        controls.maxTokens = maxTokens

        if anthropicUsesAdaptiveThinking {
            normalizeAnthropicReasoningAndMaxTokens(
                controls: &controls,
                providerType: providerType,
                modelID: modelID,
                defaultEffort: defaultEffort,
                defaultBudget: defaultBudget
            )
        } else if anthropicUsesEffortMode {
            guard let budgetTokens else { return nil }
            updateReasoning(controls: &controls) { reasoning in
                reasoning.enabled = true
                reasoning.budgetTokens = budgetTokens
            }
            normalizeAnthropicReasoningAndMaxTokens(
                controls: &controls,
                providerType: providerType,
                modelID: modelID,
                defaultEffort: defaultEffort,
                defaultBudget: defaultBudget
            )
        } else {
            guard let budgetTokens else { return nil }
            setAnthropicThinkingBudget(
                controls: &controls,
                budgetTokens: budgetTokens,
                providerType: providerType,
                modelID: modelID,
                defaultEffort: defaultEffort,
                defaultBudget: defaultBudget
            )
        }

        guard providerType == .anthropic else { return nil }
        let resolvedMax = AnthropicModelLimits.resolvedMaxTokens(
            requested: controls.maxTokens,
            for: modelID,
            fallback: 4096
        )
        return String(resolvedMax)
    }

    static func setReasoningSummary(
        controls: inout GenerationControls,
        summary: ReasoningSummary,
        supportsReasoningSummaryControl: Bool,
        defaultEffort: ReasoningEffort
    ) {
        updateReasoning(controls: &controls) { reasoning in
            reasoning.enabled = true
            reasoning.summary = summary
            if supportsReasoningSummaryControl,
               (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                reasoning.effort = defaultEffort
            }
        }
    }
}
