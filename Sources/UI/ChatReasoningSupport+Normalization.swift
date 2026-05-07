import Foundation

extension ChatReasoningSupport {
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

    static func normalizeReasoningControls(
        controls: inout GenerationControls,
        supportsReasoningControl: Bool,
        selectedReasoningConfig: ModelReasoningConfig?,
        providerType: ProviderType?,
        modelID: String,
        supportsReasoningSummaryControl: Bool,
        reasoningMustRemainEnabled: Bool,
        defaultAnthropicEffort: ReasoningEffort,
        defaultAnthropicBudget: Int
    ) {
        if supportsReasoningControl, let selectedReasoningConfig {
            switch selectedReasoningConfig.type {
            case .effort:
                normalizeEffortBasedReasoning(
                    controls: &controls,
                    config: selectedReasoningConfig,
                    providerType: providerType,
                    modelID: modelID,
                    supportsReasoningSummaryControl: supportsReasoningSummaryControl,
                    defaultAnthropicEffort: defaultAnthropicEffort,
                    defaultAnthropicBudget: defaultAnthropicBudget
                )
            case .budget:
                normalizeBudgetBasedReasoning(
                    controls: &controls,
                    config: selectedReasoningConfig
                )
            case .toggle:
                normalizeToggleBasedReasoning(controls: &controls)
            case .none:
                controls.reasoning = nil
            }
        } else if !supportsReasoningControl {
            controls.reasoning = nil
        }

        enforceReasoningAlwaysOnIfRequired(
            controls: &controls,
            reasoningMustRemainEnabled: reasoningMustRemainEnabled,
            selectedReasoningConfig: selectedReasoningConfig
        )
    }

    static func normalizeReasoningEffortLimits(
        controls: inout GenerationControls,
        supportsReasoningControl: Bool,
        providerType: ProviderType?,
        modelID: String,
        defaultAnthropicEffort: ReasoningEffort,
        defaultAnthropicBudget: Int
    ) {
        guard supportsReasoningControl else { return }

        if let effort = controls.reasoning?.effort {
            controls.reasoning?.effort = ModelCapabilityRegistry.normalizedReasoningEffort(
                effort,
                for: providerType,
                modelID: modelID
            )
        }

        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens(
                controls: &controls,
                providerType: providerType,
                modelID: modelID,
                defaultEffort: defaultAnthropicEffort,
                defaultBudget: defaultAnthropicBudget
            )
        }
    }

    private static func normalizeEffortBasedReasoning(
        controls: inout GenerationControls,
        config: ModelReasoningConfig,
        providerType: ProviderType?,
        modelID: String,
        supportsReasoningSummaryControl: Bool,
        defaultAnthropicEffort: ReasoningEffort,
        defaultAnthropicBudget: Int
    ) {
        if providerType != .anthropic,
           controls.reasoning?.enabled == true,
           controls.reasoning?.effort == nil {
            updateReasoning(controls: &controls) { reasoning in
                reasoning.effort = config.defaultEffort ?? .medium
            }
        }

        if providerType != .anthropic {
            controls.reasoning?.budgetTokens = nil
        }
        if supportsReasoningSummaryControl,
           controls.reasoning?.enabled == true,
           (controls.reasoning?.effort ?? ReasoningEffort.none) != ReasoningEffort.none,
           controls.reasoning?.summary == nil {
            controls.reasoning?.summary = .auto
        }
        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens(
                controls: &controls,
                providerType: providerType,
                modelID: modelID,
                defaultEffort: defaultAnthropicEffort,
                defaultBudget: defaultAnthropicBudget
            )
        }
    }

    private static func normalizeBudgetBasedReasoning(
        controls: inout GenerationControls,
        config: ModelReasoningConfig
    ) {
        if controls.reasoning?.enabled == true, controls.reasoning?.budgetTokens == nil {
            updateReasoning(controls: &controls) { reasoning in
                reasoning.budgetTokens = config.defaultBudget ?? 2048
            }
        }
        controls.reasoning?.effort = nil
        controls.reasoning?.summary = nil
    }

    private static func normalizeToggleBasedReasoning(controls: inout GenerationControls) {
        if controls.reasoning == nil {
            controls.reasoning = ReasoningControls(enabled: true)
        }
        controls.reasoning?.effort = nil
        controls.reasoning?.budgetTokens = nil
        controls.reasoning?.summary = nil
    }

    private static func enforceReasoningAlwaysOnIfRequired(
        controls: inout GenerationControls,
        reasoningMustRemainEnabled: Bool,
        selectedReasoningConfig: ModelReasoningConfig?
    ) {
        guard reasoningMustRemainEnabled else { return }
        if controls.reasoning == nil {
            controls.reasoning = ReasoningControls(enabled: true)
        } else {
            controls.reasoning?.enabled = true
        }

        if selectedReasoningConfig?.type == .effort,
           controls.reasoning?.effort == nil || controls.reasoning?.effort == ReasoningEffort.none {
            controls.reasoning?.effort = selectedReasoningConfig?.defaultEffort ?? .medium
        }
    }
}
