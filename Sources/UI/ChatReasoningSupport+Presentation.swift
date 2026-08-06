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
            switch controls.reasoning?.budgetTokens {
            case 1024: return "L"
            case 2048: return "M"
            case 4096: return "H"
            case 8192: return "X"
            default: return "On"
            }
        case .effort:
            guard let effort = controls.reasoning?.effort else { return "On" }
            switch effort {
            case .none: return nil
            case .minimal: return "Min"
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            case .xhigh: return "X"
            case .max: return "Max"
            }
        case .toggle:
            return "On"
        case .none:
            return nil
        }
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
