import Foundation

enum AnthropicReasoningNormalizer {
    struct Defaults {
        var effort: ReasoningEffort
        var budgetTokens: Int

        static let standard = Defaults(effort: .high, budgetTokens: 1024)
    }

    static func normalize(
        reasoning: inout ReasoningControls,
        maxTokens: inout Int?,
        modelID: String,
        defaults: Defaults = .standard
    ) {
        let usesAdaptive = AnthropicModelLimits.supportsAdaptiveThinking(for: modelID)
        let usesEffort = AnthropicModelLimits.supportsEffort(for: modelID)

        guard reasoning.enabled else {
            reasoning.effort = nil
            reasoning.budgetTokens = nil
            maxTokens = nil
            return
        }

        if usesAdaptive {
            // 4.6: adaptive thinking — effort only, no budget_tokens
            reasoning.budgetTokens = nil
            if reasoning.effort == nil || reasoning.effort == ReasoningEffort.none {
                reasoning.effort = defaults.effort
            }
        } else if usesEffort {
            // 4.5/4.1 Opus: budget_tokens + effort coexist
            if reasoning.effort == nil || reasoning.effort == ReasoningEffort.none {
                reasoning.effort = defaults.effort
            }
            if reasoning.budgetTokens == nil {
                reasoning.budgetTokens = defaults.budgetTokens
            }
        } else {
            // Older models: budget_tokens only
            reasoning.effort = nil
            if reasoning.budgetTokens == nil {
                reasoning.budgetTokens = defaults.budgetTokens
            }
        }

        maxTokens = AnthropicModelLimits.resolvedMaxTokens(
            requested: maxTokens,
            for: modelID,
            fallback: 4096
        )
    }
}
