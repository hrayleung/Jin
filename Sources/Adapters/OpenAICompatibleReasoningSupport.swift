import Foundation

/// Shared reasoning logic for OpenAI-compatible adapters (OpenAICompatible, OpenRouter).
///
/// These adapters support multiple request shapes (OpenAI Responses, OpenAI Compatible,
/// Anthropic, Gemini) and need identical reasoning application logic.
enum OpenAICompatibleReasoningSupport {

    /// Applies reasoning controls to the request body.
    /// Returns true when temperature/top_p should be omitted for compatibility.
    static func applyReasoning(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerConfig: ProviderConfig,
        modelID: String,
        requestShape: ModelRequestShape
    ) -> Bool {
        guard modelSupportsReasoning(providerConfig: providerConfig, modelID: modelID) else {
            return false
        }
        guard let reasoning = controls.reasoning else { return false }

        switch requestShape {
        case .openAIResponses, .openAICompatible:
            return applyOpenAIReasoning(
                to: &body,
                reasoning: reasoning,
                providerConfig: providerConfig,
                modelID: modelID,
                requestShape: requestShape
            )

        case .anthropic:
            return applyAnthropicReasoning(to: &body, reasoning: reasoning)

        case .gemini:
            applyGeminiReasoning(to: &body, reasoning: reasoning)
            return false
        }
    }

    // MARK: - OpenAI-Style Reasoning

    private static func applyOpenAIReasoning(
        to body: inout [String: Any],
        reasoning: ReasoningControls,
        providerConfig: ProviderConfig,
        modelID: String,
        requestShape: ModelRequestShape
    ) -> Bool {
        if reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
            body["reasoning"] = ["effort": "none"]
            return false
        }

        let effort = reasoning.effort ?? .medium
        body["reasoning"] = [
            "effort": mapReasoningEffort(effort, providerConfig: providerConfig, modelID: modelID)
        ]
        return requestShape == .openAIResponses
    }

    // MARK: - Anthropic-Style Reasoning

    private static func applyAnthropicReasoning(
        to body: inout [String: Any],
        reasoning: ReasoningControls
    ) -> Bool {
        guard reasoning.enabled else { return false }

        if let budget = reasoning.budgetTokens {
            body["thinking"] = [
                "type": "enabled",
                "budget_tokens": budget
            ]
        } else {
            body["thinking"] = ["type": "adaptive"]
            if let effort = reasoning.effort {
                mergeOutputConfig(
                    into: &body,
                    additional: ["effort": mapAnthropicEffort(effort)]
                )
            }
        }

        return true
    }

    // MARK: - Gemini-Style Reasoning

    private static func applyGeminiReasoning(
        to body: inout [String: Any],
        reasoning: ReasoningControls
    ) {
        var thinkingConfig: [String: Any] = [:]
        if reasoning.enabled {
            thinkingConfig["includeThoughts"] = true
            if let effort = reasoning.effort {
                thinkingConfig["thinkingLevel"] = mapGeminiThinkingLevel(effort)
            } else if let budget = reasoning.budgetTokens {
                thinkingConfig["thinkingBudget"] = budget
            }
        } else {
            thinkingConfig["thinkingLevel"] = "MINIMAL"
        }

        if !thinkingConfig.isEmpty {
            var generationConfig = body["generationConfig"] as? [String: Any] ?? [:]
            generationConfig["thinkingConfig"] = thinkingConfig
            body["generationConfig"] = generationConfig
        }
    }

    // MARK: - Effort Mapping

    static func mapReasoningEffort(
        _ effort: ReasoningEffort,
        providerConfig: ProviderConfig,
        modelID: String
    ) -> String {
        let normalized = ModelCapabilityRegistry.normalizedReasoningEffort(
            effort,
            for: providerConfig.type,
            modelID: modelID
        )

        switch normalized {
        case .none:
            return "none"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        }
    }

    private static func mapAnthropicEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "max"
        }
    }

    private static func mapGeminiThinkingLevel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none, .minimal:
            return "MINIMAL"
        case .low:
            return "LOW"
        case .medium:
            return "MEDIUM"
        case .high, .xhigh:
            return "HIGH"
        }
    }

    private static func mergeOutputConfig(into body: inout [String: Any], additional: [String: Any]) {
        var merged = (body["output_config"] as? [String: Any]) ?? [:]
        for (key, value) in additional {
            merged[key] = value
        }
        body["output_config"] = merged
    }
}
