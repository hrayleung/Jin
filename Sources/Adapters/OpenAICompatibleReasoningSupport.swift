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
            return applyAnthropicReasoning(to: &body, reasoning: reasoning, modelID: modelID)

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
        if isMistralReasoningEffortModel(providerConfig: providerConfig, modelID: modelID) {
            applyMistralReasoningEffort(to: &body, reasoning: reasoning)
            return false
        }

        if isGroqGPTOSSReasoningModel(providerConfig: providerConfig, modelID: modelID) {
            applyGroqGPTOSSReasoning(
                to: &body,
                reasoning: reasoning,
                providerConfig: providerConfig,
                modelID: modelID
            )
            return false
        }

        if isGroqQwenReasoningModel(providerConfig: providerConfig, modelID: modelID) {
            applyGroqQwenReasoning(
                to: &body,
                reasoning: reasoning,
                providerConfig: providerConfig,
                modelID: modelID
            )
            return false
        }

        if isCloudflareKimiK26Model(providerConfig: providerConfig, modelID: modelID) {
            let isDisabled = reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == .none
            mergeChatTemplateKwargs(
                into: &body,
                additional: ["thinking": !isDisabled]
            )

            if isDisabled {
                body.removeValue(forKey: "reasoning")
                body.removeValue(forKey: "reasoning_effort")
                return false
            }

            let effort = reasoning.effort ?? .medium
            body.removeValue(forKey: "reasoning")
            body["reasoning_effort"] = mapReasoningEffort(
                effort,
                providerConfig: providerConfig,
                modelID: modelID
            )
            return false
        }

        if providerConfig.type == .zhipuCodingPlan
            || providerConfig.type == .minimax
            || providerConfig.type == .minimaxCodingPlan
            || providerConfig.type == .mimoTokenPlanOpenAI {
            applyZhipuFamilyThinking(
                to: &body,
                reasoning: reasoning,
                providerConfig: providerConfig,
                modelID: modelID
            )
            return false
        }

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

    static func finalizeOpenAICompatibleReasoningBody(
        _ body: inout [String: Any],
        controls: GenerationControls,
        providerConfig: ProviderConfig,
        modelID: String
    ) {
        if isMistralReasoningEffortModel(providerConfig: providerConfig, modelID: modelID) {
            body.removeValue(forKey: "reasoning")
            guard let reasoning = controls.reasoning else {
                body.removeValue(forKey: "reasoning_effort")
                return
            }

            applyMistralReasoningEffort(to: &body, reasoning: reasoning)
            return
        }

        if isGroqGPTOSSReasoningModel(providerConfig: providerConfig, modelID: modelID) {
            body.removeValue(forKey: "reasoning")
            guard let reasoning = controls.reasoning else { return }
            applyGroqGPTOSSReasoning(
                to: &body,
                reasoning: reasoning,
                providerConfig: providerConfig,
                modelID: modelID
            )
            return
        }

        if isGroqQwenReasoningModel(providerConfig: providerConfig, modelID: modelID) {
            body.removeValue(forKey: "reasoning")
            guard let reasoning = controls.reasoning else {
                body.removeValue(forKey: "reasoning_effort")
                return
            }
            applyGroqQwenReasoning(
                to: &body,
                reasoning: reasoning,
                providerConfig: providerConfig,
                modelID: modelID
            )
        }
    }

    static func isMistralReasoningEffortModel(providerConfig: ProviderConfig, modelID: String) -> Bool {
        guard providerConfig.type == .mistral else { return false }
        return mistralReasoningEffortModelIDs.contains(modelID.lowercased())
    }

    private static let mistralReasoningEffortModelIDs: Set<String> = [
        "mistral-medium-3.5",
        "mistral-small-4-0-26-03",
        "magistral-medium-1-2-25-09",
    ]

    private static let groqGPTOSSReasoningModelIDs: Set<String> = [
        "openai/gpt-oss-120b",
        "openai/gpt-oss-20b",
    ]

    private static let groqQwen38ReasoningModelIDs: Set<String> = [
        "qwen/qwen3.8-27b",
    ]

    private static let groqQwen36ReasoningModelIDs: Set<String> = [
        "qwen/qwen3.6-27b",
    ]

    private static func applyMistralReasoningEffort(
        to body: inout [String: Any],
        reasoning: ReasoningControls
    ) {
        body.removeValue(forKey: "reasoning")
        let isDisabled = reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == .none
        body["reasoning_effort"] = isDisabled ? "none" : "high"
    }

    private static func isGroqGPTOSSReasoningModel(providerConfig: ProviderConfig, modelID: String) -> Bool {
        providerConfig.type == .groq
            && groqGPTOSSReasoningModelIDs.contains(modelID.lowercased())
    }

    private static func applyGroqGPTOSSReasoning(
        to body: inout [String: Any],
        reasoning: ReasoningControls,
        providerConfig: ProviderConfig,
        modelID: String
    ) {
        body.removeValue(forKey: "reasoning")
        let isDisabled = reasoning.enabled == false || (reasoning.effort ?? ReasoningEffort.none) == .none
        body["include_reasoning"] = !isDisabled
        guard !isDisabled else {
            body.removeValue(forKey: "reasoning_effort")
            return
        }

        body["reasoning_effort"] = mapReasoningEffort(
            reasoning.effort ?? .medium,
            providerConfig: providerConfig,
            modelID: modelID
        )
    }

    private static func isGroqQwenReasoningModel(providerConfig: ProviderConfig, modelID: String) -> Bool {
        guard providerConfig.type == .groq else { return false }
        let lower = modelID.lowercased()
        return groqQwen38ReasoningModelIDs.contains(lower)
            || groqQwen36ReasoningModelIDs.contains(lower)
    }

    /// Groq Chat Completions `reasoning_effort` for Qwen3 (console.groq.com/docs/models).
    /// 3.6: `none` off, omit/`default` on. 3.8: none/low/medium/high (high = native xhigh).
    private static func applyGroqQwenReasoning(
        to body: inout [String: Any],
        reasoning: ReasoningControls,
        providerConfig: ProviderConfig,
        modelID: String
    ) {
        body.removeValue(forKey: "reasoning")
        body.removeValue(forKey: "include_reasoning")
        let lower = modelID.lowercased()
        let isExplicitlyOff = reasoning.enabled == false || reasoning.effort == ReasoningEffort.none

        if groqQwen36ReasoningModelIDs.contains(lower) {
            if isExplicitlyOff {
                body["reasoning_effort"] = "none"
            } else {
                body.removeValue(forKey: "reasoning_effort")
            }
            return
        }

        if isExplicitlyOff {
            body["reasoning_effort"] = "none"
            return
        }

        let effort = reasoning.effort ?? .none
        switch effort {
        case .low, .medium, .high:
            body["reasoning_effort"] = effort.rawValue
        case .xhigh, .max:
            body["reasoning_effort"] = "high"
        case .none, .minimal:
            body["reasoning_effort"] = "none"
        }
    }

    // MARK: - Anthropic-Style Reasoning

    private static func applyAnthropicReasoning(
        to body: inout [String: Any],
        reasoning: ReasoningControls,
        modelID: String
    ) -> Bool {
        guard reasoning.enabled else { return false }

        // Sonnet 5 / Fable / Opus 5 adaptive thinking rejects `budget_tokens`.
        // Mid-conversation switches leave the previous model's budget on `reasoning`.
        if AnthropicModelLimits.supportsAdaptiveThinking(for: modelID) {
            body["thinking"] = AnthropicThinkingConfigSupport.normalizedThinkingConfiguration(
                ["type": "adaptive"],
                reasoning: reasoning,
                modelID: modelID
            )
            if let effort = reasoning.effort, effort != .none {
                mergeOutputConfig(
                    into: &body,
                    additional: ["effort": mapAnthropicEffort(effort)]
                )
            }
            return true
        }

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

    // MARK: - Zhipu / MiniMax / MiMo thinking

    /// Zhipu Coding Plan, MiniMax, and MiMo Token Plan share the `thinking.type`
    /// enabled/disabled envelope. GLM-5.3 additionally requires `reasoning_effort`
    /// and rejects `thinking.type: disabled` (z.ai/blog/glm-5.3). GLM-5.2 takes
    /// `reasoning_effort` high/max when thinking is on (docs.z.ai/devpack/latest-model).
    private static func applyZhipuFamilyThinking(
        to body: inout [String: Any],
        reasoning: ReasoningControls,
        providerConfig: ProviderConfig,
        modelID: String
    ) {
        let lowerModelID = modelID.lowercased()
        let isGLM53 = isZhipuGLM53ModelID(lowerModelID)
        let isDisabled = !isGLM53 && (!reasoning.enabled || reasoning.effort == ReasoningEffort.none)

        body["thinking"] = [
            "type": isDisabled ? "disabled" : "enabled"
        ]

        guard providerConfig.type == .zhipuCodingPlan, !isDisabled else { return }

        if isGLM53 {
            let effort = glm53ReasoningEffortWireValue(from: reasoning)
            body["reasoning_effort"] = effort
            return
        }

        if isZhipuGLM52ModelID(lowerModelID) {
            let effort = reasoning.effort ?? .high
            body["reasoning_effort"] = (effort == .max || effort == .xhigh) ? "max" : "high"
        }
    }

    private static func isZhipuGLM53ModelID(_ lowerModelID: String) -> Bool {
        switch lowerModelID {
        case "glm-5.3", "glm-5.3[1m]", "glm-5.3-flash":
            return true
        default:
            return false
        }
    }

    private static func isZhipuGLM52ModelID(_ lowerModelID: String) -> Bool {
        switch lowerModelID {
        case "glm-5.2", "glm-5.2[1m]":
            return true
        default:
            return false
        }
    }

    /// Official GLM-5.3 band is low/high/max. Disabled thinking is no longer
    /// accepted and must be sent as `low` (z.ai/blog/glm-5.3).
    private static func glm53ReasoningEffortWireValue(from reasoning: ReasoningControls) -> String {
        if !reasoning.enabled || reasoning.effort == ReasoningEffort.none {
            return "low"
        }
        switch reasoning.effort ?? .max {
        case .none, .minimal, .low:
            return "low"
        case .medium, .high:
            return "high"
        case .xhigh, .max:
            return "max"
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
        case .minimal:
            // "minimal" is a real wire value for models whose band pins it (e.g.
            // google/gemini-3.1-flash-lite-image on OpenRouter, band minimal/high).
            // Normalization already clamps .minimal away for every other model on
            // this path, so the fold to "low" only remains as a defensive tail.
            return ModelCapabilityRegistry.supportedReasoningEfforts(
                for: providerConfig.type,
                modelID: modelID
            ).contains(.minimal) ? "minimal" : "low"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        case .max:
            // `max` is a real API value starting with GPT-5.6 (and for OpenRouter
            // models whose band includes it, e.g. sakana/fugu-ultra); older models
            // reject it and stay clamped to xhigh.
            return ModelCapabilityRegistry.supportsOpenAIStyleMaxEffort(for: providerConfig.type, modelID: modelID)
                ? "max"
                : "xhigh"
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
            return "xhigh"
        case .max:
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
        case .high, .xhigh, .max:
            return "HIGH"
        }
    }

    private static func mergeOutputConfig(into body: inout [String: Any], additional: [String: Any]) {
        let existing = (body["output_config"] as? [String: Any]) ?? [:]
        body["output_config"] = existing.merging(additional) { _, new in new }
    }

    static func isCloudflareKimiK26Model(providerConfig: ProviderConfig, modelID: String) -> Bool {
        providerConfig.type == .cloudflareAIGateway
            && modelID.lowercased() == "@cf/moonshotai/kimi-k2.6"
    }

    static func mergeChatTemplateKwargs(into body: inout [String: Any], additional: [String: Any]) {
        let existing = (body["chat_template_kwargs"] as? [String: Any]) ?? [:]
        body["chat_template_kwargs"] = existing.merging(additional) { _, new in new }
    }
}
