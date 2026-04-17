import Foundation

enum AnthropicThinkingConfigSupport {
    static func providerSpecificThinkingDictionary(from value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let codableDictionary = value as? [String: AnyCodable] {
            return codableDictionary.mapValues { $0.value }
        }
        return nil
    }

    static func resolvedThinkingDisplay(
        from reasoning: ReasoningControls?,
        modelID: String
    ) -> AnthropicThinkingDisplay? {
        guard AnthropicModelLimits.requiresExplicitThinkingDisplay(for: modelID) else { return nil }
        return reasoning?.anthropicThinkingDisplay ?? .summarized
    }

    static func normalizedThinkingConfiguration(
        _ config: [String: Any],
        reasoning: ReasoningControls?,
        modelID: String
    ) -> [String: Any] {
        var normalized = config

        if AnthropicModelLimits.supportsAdaptiveThinking(for: modelID) {
            normalized["type"] = "adaptive"
            normalized.removeValue(forKey: "budget_tokens")
            if let display = resolvedThinkingDisplay(from: reasoning, modelID: modelID) {
                normalized["display"] = display.rawValue
            }
        } else if normalized["type"] as? String == "adaptive" {
            normalized["type"] = "enabled"
        }

        return normalized
    }
}
