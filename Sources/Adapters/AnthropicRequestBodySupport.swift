import Foundation

enum AnthropicRequestBodySupport {
    static func applySystemPrompt(
        to body: inout [String: Any],
        from messages: [Message],
        cacheControl: [String: Any]?
    ) {
        guard let systemPrompt = messages.first(where: { $0.role == .system })?.content.first,
              case .text(let text) = systemPrompt else {
            return
        }

        var block: [String: Any] = [
            "type": "text",
            "text": text
        ]
        if let cacheControl {
            block["cache_control"] = cacheControl
        }
        body["system"] = [block]
    }

    /// Injects `"speed": "fast"` into the Messages API request body when fast
    /// mode is enabled on a supported Opus model on direct Anthropic. The beta
    /// header `fast-mode-2026-02-01` must also be set on the request — see
    /// `AnthropicRequestPreparationSupport.betaHeader(...)`.
    static func applySpeedConfig(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerType: ProviderType,
        modelID: String
    ) {
        guard providerType == .anthropic,
              controls.anthropicSpeed == .fast,
              AnthropicModelLimits.supportsFastMode(for: modelID) else {
            return
        }
        body["speed"] = "fast"
    }

    static func applyThinkingConfig(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerType: ProviderType,
        modelID: String
    ) {
        let thinkingEnabled = controls.reasoning?.enabled == true
        let providerSpecificThinking = AnthropicThinkingConfigSupport.providerSpecificThinkingDictionary(
            from: controls.providerSpecific["thinking"]?.value
        )

        if providerType == .mimoTokenPlanAnthropic {
            if let providerSpecificThinking {
                body["thinking"] = AnthropicThinkingConfigSupport.normalizedThinkingConfiguration(
                    providerSpecificThinking,
                    reasoning: controls.reasoning,
                    modelID: modelID
                )
            } else if controls.reasoning != nil {
                body["thinking"] = ["type": thinkingEnabled ? "enabled" : "disabled"]
            }
            applySamplingControls(to: &body, controls: controls, modelID: modelID)
            return
        }

        if providerType == .kimiForCoding {
            // Kimi K2.7 Code is thinking-always-on ("Thinking: ON" in the Kimi Code
            // docs); requests without thinking are silently routed to K2.6, so force
            // the thinking field regardless of the persisted toggle state. K3
            // supports only effort "max", which the endpoint applies when `thinking`
            // is omitted (docs: null/undefined → max) — send nothing for it rather
            // than an undocumented budget shape.
            let lowerModelID = modelID.lowercased()
            if lowerModelID == "kimi-for-coding" || lowerModelID == "kimi-for-coding-highspeed" {
                body["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": controls.reasoning?.budgetTokens ?? 2048
                ]
            }
            applySamplingControls(to: &body, controls: controls, modelID: modelID)
            return
        }

        if !thinkingEnabled {
            // `controls.reasoning == nil` means no preference was ever set (e.g. a fresh
            // conversation) — leave `thinking` omitted so models whose default is adaptive-on
            // (Sonnet 5, Opus 5, Fable) keep thinking. Only an explicit `enabled == false`
            // means the user turned it off. Opus 5 still needs `{type: "disabled"}` for that;
            // Sonnet 5 / Fable 5 reject disabled (always-on), so the field is omitted.
            let explicitlyDisabled = controls.reasoning?.enabled == false
            if AnthropicModelLimits.supportsDeepSeekV4OutputConfigEffort(for: modelID)
                || (explicitlyDisabled && AnthropicModelLimits.requiresExplicitThinkingDisabled(for: modelID)) {
                body["thinking"] = ["type": "disabled"]
            }
            applySamplingControls(to: &body, controls: controls, modelID: modelID)
            return
        }

        // Always rewrite thinking for the *current* model. Mid-conversation switches
        // leave the previous model's `providerSpecific["thinking"]` (often
        // `{type:"enabled", budget_tokens:N}` from Haiku/Sonnet 4.5). Skipping that
        // leftover would send `thinking.budget_tokens`, which Sonnet 5 / Fable / Opus 5
        // reject as extra input.
        if AnthropicModelLimits.supportsAdaptiveThinking(for: modelID) {
            let base = providerSpecificThinking ?? ["type": "adaptive"]
            body["thinking"] = AnthropicThinkingConfigSupport.normalizedThinkingConfiguration(
                base,
                reasoning: controls.reasoning,
                modelID: modelID
            )
        } else if providerSpecificThinking == nil {
            if AnthropicModelLimits.supportsDeepSeekV4OutputConfigEffort(for: modelID) {
                body["thinking"] = ["type": "enabled"]
            } else {
                body["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": controls.reasoning?.budgetTokens ?? 2048
                ]
            }
        }

        if AnthropicModelLimits.supportsEffort(for: modelID),
           let effort = controls.reasoning?.effort,
           effort != .none {
            mergeOutputConfig(
                into: &body,
                additional: ["effort": mapAnthropicEffort(effort, modelID: modelID)]
            )
        }
    }

    static func applyToolSpecs(
        to body: inout [String: Any],
        controls: GenerationControls,
        customTools: [[String: Any]],
        supportsWebSearch: Bool,
        supportsDynamicFiltering: Bool,
        codeExecutionEnabled: Bool
    ) {
        var toolSpecs: [[String: Any]] = []

        if let webSearch = controls.webSearch,
           webSearch.enabled,
           supportsWebSearch {
            toolSpecs.append(
                AnthropicToolSpecSupport.webSearchToolSpec(
                    from: webSearch,
                    supportsDynamicFiltering: supportsDynamicFiltering
                )
            )
        }

        if codeExecutionEnabled {
            toolSpecs.append(AnthropicToolSpecSupport.codeExecutionToolSpec())
        }

        toolSpecs.append(contentsOf: customTools)

        if !toolSpecs.isEmpty {
            body["tools"] = toolSpecs
        }
    }

    static func applyProviderSpecificOverrides(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String,
        supportsDynamicFiltering: Bool
    ) {
        for (key, value) in controls.providerSpecific {
            if key == "anthropic_beta" || key == "anthropic-beta" {
                continue
            }

            if (key == "temperature" || key == "top_p" || key == "top_k")
                && !AnthropicModelLimits.supportsSamplingParameters(for: modelID) {
                continue
            }

            if key == "tools" {
                body[key] = AnthropicToolSpecSupport.normalizedProviderSpecificTools(
                    value.value,
                    supportsDynamicFiltering: supportsDynamicFiltering
                )
                continue
            }

            if key == "thinking" {
                guard controls.reasoning?.enabled == true,
                      let dict = AnthropicThinkingConfigSupport.providerSpecificThinkingDictionary(from: value.value) else {
                    continue
                }
                body[key] = AnthropicThinkingConfigSupport.normalizedThinkingConfiguration(
                    dict,
                    reasoning: controls.reasoning,
                    modelID: modelID
                )
                continue
            }

            if key == "output_format" {
                mergeOutputConfig(into: &body, additional: ["format": value.value])
                continue
            }

            if key == "output_config", let dict = providerSpecificJSONDictionary(value.value) {
                mergeOutputConfig(into: &body, additional: dict)
                continue
            }

            body[key] = value.value
        }
    }

    static func blockCacheControl(
        from contextCache: ContextCacheControls?,
        strategy: ContextCacheStrategy
    ) -> [String: Any]? {
        guard strategy != .prefixWindow else { return nil }
        return ephemeralCacheControl(from: contextCache)
    }

    static func topLevelCacheControl(
        from contextCache: ContextCacheControls?,
        strategy: ContextCacheStrategy
    ) -> [String: Any]? {
        guard strategy == .prefixWindow else { return nil }
        return ephemeralCacheControl(from: contextCache)
    }

    static func mapAnthropicEffort(_ effort: ReasoningEffort, modelID: String) -> String {
        if AnthropicModelLimits.supportsDeepSeekV4OutputConfigEffort(for: modelID) {
            switch effort {
            case .xhigh, .max:
                return "max"
            default:
                return "high"
            }
        }

        let normalized = ModelCapabilityRegistry.normalizedReasoningEffort(
            effort,
            for: .anthropic,
            modelID: modelID
        )

        switch normalized {
        case .none:
            return "high"
        case .minimal, .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .xhigh:
            return "xhigh"
        case .max:
            return AnthropicModelLimits.supportsMaxEffort(for: modelID) ? "max" : "high"
        }
    }

    private static func applySamplingControls(
        to body: inout [String: Any],
        controls: GenerationControls,
        modelID: String
    ) {
        guard AnthropicModelLimits.supportsSamplingParameters(for: modelID) else { return }
        if let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }
    }

    private static func providerSpecificJSONDictionary(_ value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let codableDictionary = value as? [String: AnyCodable] {
            return codableDictionary.mapValues { $0.value }
        }
        return nil
    }

    /// Adaptive-thinking models (Sonnet 5, Fable, Opus 5, 4.8/4.7/4.6) reject
    /// `thinking.budget_tokens` as extra input. Strip it after every mutator so a
    /// leftover `{type:"enabled", budget_tokens:N}` from a previous model in the
    /// same conversation cannot reach the API.
    static func sanitizeAdaptiveThinking(in body: inout [String: Any], modelID: String) {
        guard AnthropicModelLimits.supportsAdaptiveThinking(for: modelID),
              var thinking = body["thinking"] as? [String: Any] else { return }
        thinking.removeValue(forKey: "budget_tokens")
        thinking.removeValue(forKey: "budgetTokens")
        if unwrappedString(thinking["type"]) == "enabled" {
            thinking["type"] = "adaptive"
        }
        body["thinking"] = thinking
    }

    /// Opus 5 rejects `thinking: {type: "disabled"}` paired with an effort of `xhigh`/`max`
    /// with a 400, and the API validates that pairing on every request. Jin's own effort is
    /// only emitted on the thinking-enabled path, but a persisted provider-specific
    /// `output_config` can still carry one, so clamp to `high` as the final normalization
    /// before the body is serialized.
    static func normalizeDisabledThinkingEffort(in body: inout [String: Any], modelID: String) {
        guard AnthropicModelLimits.disabledThinkingRequiresEffortAtMostHigh(for: modelID),
              let thinking = body["thinking"] as? [String: Any],
              unwrappedString(thinking["type"]) == "disabled",
              var outputConfig = body["output_config"] as? [String: Any],
              let effort = unwrappedString(outputConfig["effort"]),
              effort == "xhigh" || effort == "max" else {
            return
        }

        outputConfig["effort"] = "high"
        body["output_config"] = outputConfig
    }

    private static func unwrappedString(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let codable = value as? AnyCodable {
            return codable.value as? String
        }
        return nil
    }

    private static func mergeOutputConfig(into body: inout [String: Any], additional: [String: Any]) {
        guard !additional.isEmpty else { return }
        var merged = (body["output_config"] as? [String: Any]) ?? [:]
        for (key, value) in additional {
            merged[key] = value
        }
        body["output_config"] = merged
    }

    private static func ephemeralCacheControl(from contextCache: ContextCacheControls?) -> [String: Any]? {
        let mode = contextCache?.mode ?? .implicit
        guard mode != .off else { return nil }

        var out: [String: Any] = ["type": "ephemeral"]
        if let ttl = contextCache?.ttl?.providerTTLString {
            out["ttl"] = ttl
        }
        return out
    }
}
