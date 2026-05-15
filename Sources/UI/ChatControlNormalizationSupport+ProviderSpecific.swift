import Foundation

extension ChatControlNormalizationSupport {
    static func normalizeVertexAIGenerationConfig(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        lowerModelID: String,
        vertexGemini25TextModelIDs: Set<String>
    ) {
        guard providerType == .vertexai,
              var generationConfig = controls.providerSpecific["generationConfig"]?.value as? [String: Any] else {
            return
        }

        var mutated = false

        if lowerModelID == "gemini-3-pro-image-preview"
            || lowerModelID == "gemini-3.1-flash-image-preview" {
            if generationConfig["thinkingConfig"] != nil {
                generationConfig.removeValue(forKey: "thinkingConfig")
                mutated = true
            }
        } else if vertexGemini25TextModelIDs.contains(lowerModelID),
                  var thinkingConfig = generationConfig["thinkingConfig"] as? [String: Any],
                  thinkingConfig["thinkingLevel"] != nil {
            thinkingConfig.removeValue(forKey: "thinkingLevel")
            if thinkingConfig.isEmpty {
                generationConfig.removeValue(forKey: "thinkingConfig")
            } else {
                generationConfig["thinkingConfig"] = thinkingConfig
            }
            mutated = true
        }

        guard mutated else { return }
        if generationConfig.isEmpty {
            controls.providerSpecific.removeValue(forKey: "generationConfig")
        } else {
            controls.providerSpecific["generationConfig"] = AnyCodable(generationConfig)
        }
    }

    static func normalizeFireworksProviderSpecific(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        isMiniMaxM2FamilyModel: Bool,
        fireworksReasoningHistoryOptions: [String]
    ) {
        guard providerType == .fireworks else { return }

        if isMiniMaxM2FamilyModel {
            controls.providerSpecific.removeValue(forKey: "reasoning_effort")
        }

        if let rawHistory = controls.providerSpecific["reasoning_history"]?.value as? String {
            let normalized = rawHistory.lowercased()
            if fireworksReasoningHistoryOptions.contains(normalized) {
                controls.providerSpecific["reasoning_history"] = AnyCodable(normalized)
            } else {
                controls.providerSpecific.removeValue(forKey: "reasoning_history")
            }
        } else if controls.providerSpecific["reasoning_history"] != nil {
            controls.providerSpecific.removeValue(forKey: "reasoning_history")
        }
    }

    static func normalizeAnthropicProviderSpecific(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        modelID: String
    ) {
        guard providerType == .anthropic else { return }

        if !AnthropicModelLimits.supportsSamplingParameters(for: modelID) {
            controls.providerSpecific.removeValue(forKey: "temperature")
            controls.providerSpecific.removeValue(forKey: "top_p")
            controls.providerSpecific.removeValue(forKey: "top_k")
        }

        guard controls.reasoning?.enabled == true else {
            controls.providerSpecific.removeValue(forKey: "thinking")
            return
        }

        guard let thinking = AnthropicThinkingConfigSupport.providerSpecificThinkingDictionary(
            from: controls.providerSpecific["thinking"]?.value
        ) else {
            controls.providerSpecific.removeValue(forKey: "thinking")
            return
        }

        controls.providerSpecific["thinking"] = AnyCodable(
            AnthropicThinkingConfigSupport.normalizedThinkingConfiguration(
                thinking,
                reasoning: controls.reasoning,
                modelID: modelID
            )
        )
    }

    static func normalizeClaudeManagedAgentProviderSpecific(
        controls: inout GenerationControls,
        providerType: ProviderType?
    ) {
        guard providerType == .claudeManagedAgents else {
            sanitizeProviderSpecificForProvider(providerType, controls: &controls)
            return
        }

        controls.normalizeClaudeManagedAgentProviderSpecific(for: providerType)
    }

    static func normalizeOpenAIServiceTierControls(controls: inout GenerationControls) {
        if controls.openAIServiceTier == nil,
           let legacyRaw = controls.providerSpecific["service_tier"]?.value as? String,
           let legacy = OpenAIServiceTier.normalized(rawValue: legacyRaw) {
            controls.openAIServiceTier = legacy
        }

        if controls.providerSpecific["service_tier"] != nil {
            controls.providerSpecific.removeValue(forKey: "service_tier")
        }
    }

    nonisolated static func sanitizeProviderSpecificForProvider(
        _ providerType: ProviderType?,
        controls: inout GenerationControls
    ) {
        if providerType != .claudeManagedAgents {
            controls.removeClaudeManagedAgentProviderSpecificKeys()
        }
    }

    static func normalizeAnthropicMaxTokens(
        controls: inout GenerationControls,
        supportsReasoningControl: Bool,
        providerType: ProviderType?
    ) {
        if !supportsReasoningControl, providerType == .anthropic {
            controls.maxTokens = nil
        }
        if providerType == .anthropic,
           controls.maxTokens != nil,
           controls.reasoning?.enabled != true {
            controls.maxTokens = nil
        }
    }
}
