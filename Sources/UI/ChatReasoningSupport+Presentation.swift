import Foundation

extension ChatReasoningSupport {
    static func reasoningHelpText(
        supportsReasoningControl: Bool,
        providerType: ProviderType?,
        label: String
    ) -> String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .claudeManagedAgents, .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .gemini, .vertexai, .kimiForCoding:
            return "Thinking: \(label)"
        case .perplexity:
            return "Reasoning: \(label)"
        case .openai, .openaiWebSocket, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway,
             .openrouter, .groq, .cohere, .mistral, .deepinfra, .together, .baseten, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .databricks, .modal, .morphllm, .opencodeGo,
             .zyphra, .meta, .none:
            return "Reasoning: \(label)"
        }
    }

    static func reasoningBadgeText(
        supportsReasoningControl: Bool,
        isReasoningEnabled: Bool,
        selectedReasoningConfig: ModelReasoningConfig?,
        controls: GenerationControls
    ) -> String? {
        guard supportsReasoningControl, isReasoningEnabled else { return nil }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return nil }

        switch reasoningType {
        case .budget:
            guard let tokens = controls.reasoning?.budgetTokens else { return "On" }
            return formatBudgetBadge(tokens)
        case .effort:
            guard let effort = controls.reasoning?.effort else { return "On" }
            return effort.badgeName
        case .toggle:
            return "On"
        case .none:
            return nil
        }
    }

    /// Compact human-readable label for a token budget (e.g. "1K", "8K").
    private static func formatBudgetBadge(_ tokens: Int) -> String {
        if tokens >= 1000, tokens % 1000 == 0 {
            return "\(tokens / 1000)K"
        }
        return "\(tokens)"
    }

    /// Effort levels rendered next to the dedicated "Off" disable row.
    ///
    /// `ReasoningEffort.none.displayName` is also `"Off"`. When the composer already
    /// shows a disable toggle, including `.none` would duplicate that label (e.g. Kimi
    /// K3 on Baseten/Modal/Fireworks: Off, Off, Low, High, Max). Keep `.none` only when
    /// the disable toggle is unavailable — it is then the sole "Off" affordance.
    static func effortLevelsForReasoningMenu(
        supported: [ReasoningEffort],
        includesDisableToggle: Bool
    ) -> [ReasoningEffort] {
        guard includesDisableToggle else { return supported }
        return supported.filter { $0 != .none }
    }

    /// Whether the dedicated "Off" row should appear selected.
    ///
    /// Treats explicit `effort == .none` as Off when the disable toggle owns that
    /// label, so a previously selected `.none` effort still highlights correctly.
    static func isReasoningOffMenuSelected(
        isReasoningEnabled: Bool,
        currentEffort: ReasoningEffort?,
        includesDisableToggle: Bool
    ) -> Bool {
        if !isReasoningEnabled {
            return true
        }
        if includesDisableToggle, currentEffort == ReasoningEffort.none {
            return true
        }
        return false
    }
}
