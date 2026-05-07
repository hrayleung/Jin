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

    static func supportsAnthropicThinkingDisplayControl(providerType: ProviderType?, modelID: String) -> Bool {
        guard providerType == .anthropic else { return false }
        return AnthropicModelLimits.requiresExplicitThinkingDisplay(for: modelID)
    }

    static func resolvedAnthropicThinkingDisplay(
        currentDisplay: AnthropicThinkingDisplay?,
        providerType: ProviderType?,
        modelID: String
    ) -> AnthropicThinkingDisplay {
        guard supportsAnthropicThinkingDisplayControl(providerType: providerType, modelID: modelID) else {
            return .summarized
        }
        return currentDisplay ?? .summarized
    }

    static func updateReasoning(
        controls: inout GenerationControls,
        mutate: (inout ReasoningControls) -> Void
    ) {
        var reasoning = controls.reasoning ?? ReasoningControls(enabled: false)
        mutate(&reasoning)
        controls.reasoning = reasoning
    }
}
