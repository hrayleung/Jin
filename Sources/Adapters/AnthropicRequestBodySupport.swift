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

        if !thinkingEnabled {
            if AnthropicModelLimits.supportsDeepSeekV4OutputConfigEffort(for: modelID) {
                body["thinking"] = ["type": "disabled"]
            }
            applySamplingControls(to: &body, controls: controls, modelID: modelID)
            return
        }

        if providerSpecificThinking == nil {
            if AnthropicModelLimits.supportsAdaptiveThinking(for: modelID) {
                body["thinking"] = AnthropicThinkingConfigSupport.normalizedThinkingConfiguration(
                    ["type": "adaptive"],
                    reasoning: controls.reasoning,
                    modelID: modelID
                )
            } else if AnthropicModelLimits.supportsDeepSeekV4OutputConfigEffort(for: modelID) {
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
