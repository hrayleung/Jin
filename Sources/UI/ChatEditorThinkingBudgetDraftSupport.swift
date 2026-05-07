import Foundation

extension ChatEditorDraftSupport {
    static func thinkingBudgetDraftInt(from raw: String) -> Int? {
        Int(raw.trimmed)
    }

    static func maxTokensDraftInt(from raw: String) -> Int? {
        guard let trimmed = raw.trimmedNonEmpty,
              let value = Int(trimmed),
              value > 0 else { return nil }
        return value
    }

    static func resolvedAnthropicMaxTokensDraftInt(
        from raw: String,
        currentMaxTokens: Int?,
        modelID: String
    ) -> Int? {
        if raw.trimmedNonEmpty == nil {
            let fallback = currentMaxTokens ?? AnthropicModelLimits.resolvedMaxTokens(
                requested: nil,
                for: modelID,
                fallback: 4096
            )
            return fallback > 0 ? fallback : nil
        }
        return maxTokensDraftInt(from: raw)
    }

    static func prepareThinkingBudgetEditorDraft(
        anthropicUsesAdaptiveThinking: Bool,
        budgetTokens: Int?,
        defaultBudget: Int,
        providerType: ProviderType?,
        requestedMaxTokens: Int?,
        modelID: String
    ) -> PreparedThinkingBudgetEditorDraft {
        let thinkingBudgetDraft: String
        if anthropicUsesAdaptiveThinking {
            thinkingBudgetDraft = ""
        } else {
            thinkingBudgetDraft = "\(budgetTokens ?? defaultBudget)"
        }

        let maxTokensDraft: String
        if providerType == .anthropic {
            let resolvedMax = AnthropicModelLimits.resolvedMaxTokens(
                requested: requestedMaxTokens,
                for: modelID,
                fallback: 4096
            )
            maxTokensDraft = "\(resolvedMax)"
        } else {
            maxTokensDraft = requestedMaxTokens.map(String.init) ?? ""
        }

        return PreparedThinkingBudgetEditorDraft(
            thinkingBudgetDraft: thinkingBudgetDraft,
            maxTokensDraft: maxTokensDraft
        )
    }

    static func isThinkingBudgetDraftValid(
        anthropicUsesAdaptiveThinking: Bool,
        providerType: ProviderType?,
        modelID: String,
        thinkingBudgetDraft: String,
        maxTokensDraft: String,
        currentMaxTokens: Int?
    ) -> Bool {
        if !anthropicUsesAdaptiveThinking {
            guard let budget = thinkingBudgetDraftInt(from: thinkingBudgetDraft), budget > 0 else { return false }
        }
        guard providerType == .anthropic else { return true }
        guard let maxTokens = resolvedAnthropicMaxTokensDraftInt(
            from: maxTokensDraft,
            currentMaxTokens: currentMaxTokens,
            modelID: modelID
        ) else { return false }
        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: modelID), maxTokens > modelMax {
            return false
        }
        return true
    }

    static func thinkingBudgetValidationWarning(
        providerType: ProviderType?,
        anthropicUsesAdaptiveThinking: Bool,
        modelID: String,
        thinkingBudgetDraft: String,
        maxTokensDraft: String,
        currentMaxTokens: Int?
    ) -> String? {
        guard providerType == .anthropic else { return nil }

        let thinkingBudgetDraftInt = thinkingBudgetDraftInt(from: thinkingBudgetDraft)
        let hasMaxTokensDraft = maxTokensDraft.trimmedNonEmpty != nil
        let maxTokensDraftInt = resolvedAnthropicMaxTokensDraftInt(
            from: maxTokensDraft,
            currentMaxTokens: currentMaxTokens,
            modelID: modelID
        )

        if !anthropicUsesAdaptiveThinking {
            guard let budget = thinkingBudgetDraftInt else { return "Enter an integer token budget (e.g., 4096)." }

            if budget <= 0 {
                return "Thinking budget must be a positive integer."
            }

            if let maxTokens = maxTokensDraftInt, maxTokens > 0, budget >= maxTokens {
                return "Recommended: keep budget tokens below max output tokens."
            }
        }

        if hasMaxTokensDraft && maxTokensDraftInt == nil {
            return "Enter a valid positive max output token value."
        }

        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: modelID),
           let maxTokens = maxTokensDraftInt,
           maxTokens > modelMax {
            return "This model allows at most \(modelMax) max output tokens."
        }

        return nil
    }
}
