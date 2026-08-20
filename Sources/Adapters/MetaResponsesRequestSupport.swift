import Foundation

enum MetaResponsesRequestSupport {
    static func responsesBody(
        modelID: String,
        input: [[String: Any]],
        streaming: Bool,
        controls: GenerationControls,
        functionTools: [[String: Any]],
        webSearchEnabled: Bool,
        providerType: ProviderType
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": modelID,
            "input": input,
            "stream": streaming,
            // Stateless encrypted CoT replay (Meta docs): keep no server history and
            // request encrypted reasoning so tool-loop turns can re-send CoT.
            "store": false
        ]

        applySamplingControls(to: &body, controls: controls)
        applyReasoningConfig(
            to: &body,
            controls: controls,
            providerType: providerType,
            modelID: modelID
        )
        if providerType.supportsNativePromptCaching {
            applyContextCacheControls(to: &body, controls: controls)
        }

        var toolObjects: [[String: Any]] = []
        if webSearchEnabled {
            toolObjects.append(["type": "web_search"])
        }
        toolObjects.append(contentsOf: functionTools)
        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        // Always request encrypted reasoning for multi-turn / tool-loop continuity.
        // Cannot be combined with previous_response_id (we never send that).
        body["include"] = OpenAIResponsesRequestSupport.mergedIncludeFields(
            body["include"],
            adding: "reasoning.encrypted_content"
        )
        if webSearchEnabled {
            body["include"] = OpenAIResponsesRequestSupport.mergedIncludeFields(
                body["include"],
                adding: "web_search_call.results"
            )
        }

        // Only forward provider-specific keys that Meta is likely to accept; never
        // overwrite computed reasoning/tools/input.
        let protectedKeys: Set<String> = [
            "model", "input", "stream", "store", "tools", "reasoning", "include",
            "temperature", "top_p", "max_output_tokens",
            "prompt_cache_key", "prompt_cache_retention"
        ]
        for (key, value) in controls.providerSpecific where !protectedKeys.contains(key) {
            body[key] = value.value
        }

        return body
    }

    /// Prefer temperature when both sampling knobs are set (Meta documents
    /// temperature-or-top_p on Chat Completions; apply the same safety on Responses).
    static func applySamplingControls(to body: inout [String: Any], controls: GenerationControls) {
        if let temperature = controls.temperature {
            body["temperature"] = temperature
        } else if let topP = controls.topP {
            body["top_p"] = topP
        }

        if let maxTokens = controls.maxTokens {
            body["max_output_tokens"] = maxTokens
        }
    }

    /// Nested `reasoning.effort` on Responses. Always-on Muse Spark: omit entirely
    /// when disabled/none (sending `"none"` returns HTTP 400). Map `.max` → `xhigh`.
    static func applyReasoningConfig(
        to body: inout [String: Any],
        controls: GenerationControls,
        providerType: ProviderType,
        modelID: String
    ) {
        guard let reasoning = controls.reasoning, reasoning.enabled else { return }

        let effort = ModelCapabilityRegistry.normalizedReasoningEffort(
            reasoning.effort ?? .medium,
            for: providerType,
            modelID: modelID
        )

        let wire: String?
        switch effort {
        case .none:
            wire = nil
        case .minimal:
            wire = "minimal"
        case .low:
            wire = "low"
        case .medium:
            wire = "medium"
        case .high:
            wire = "high"
        case .xhigh, .max:
            wire = "xhigh"
        }

        if let wire {
            body["reasoning"] = ["effort": wire]
        }
    }

    /// Meta accepts `prompt_cache_retention` of `in_memory` | `24h` only (not OpenAI's 5m/1h).
    static func applyContextCacheControls(to body: inout [String: Any], controls: GenerationControls) {
        guard controls.contextCache?.mode != .off else { return }

        if let cacheKey = normalizedTrimmedString(controls.contextCache?.cacheKey) {
            body["prompt_cache_key"] = cacheKey
        }

        if let retention = metaPromptCacheRetention(for: controls.contextCache?.ttl) {
            body["prompt_cache_retention"] = retention
        }
    }

    static func metaPromptCacheRetention(for ttl: ContextCacheTTL?) -> String? {
        guard let ttl else { return nil }
        switch ttl {
        case .providerDefault:
            return nil
        case .minutes5:
            return "in_memory"
        case .hour1:
            return "24h"
        case .customSeconds(let seconds):
            return seconds >= 3_600 ? "24h" : "in_memory"
        }
    }
}
