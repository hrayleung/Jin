import Foundation

extension ModelCatalog {
    static let mistralRecords: [Record] = [
        // Seeded — appear in the model picker on first launch
        // Mistral Medium 3.5 is seeded as the legacy short alias `mistral-medium-3.5` below.
        Record(id: "mistral-medium-3-5-26-04", displayName: "Mistral Medium 3.5",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "mistral-large-3-25-12", displayName: "Mistral Large 3",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: true),
        // Mistral Large 4 (public preview 2026-10-06, docs.mistral.ai changelog
        // + model card): 1M context, multimodal, function calling, structured
        // outputs, reasoning_effort none|high (default high).
        Record(id: "mistral-large-4", displayName: "Mistral Large 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_000_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high,
                                                     supportedEfforts: [.none, .high]),
               isFullySupported: true, isSeeded: true),
        Record(id: "mistral-small-4-0-26-03", displayName: "Mistral Small 4",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .toggle),
               isFullySupported: true, isSeeded: true),
        Record(id: "magistral-medium-1-2-25-09", displayName: "Magistral Medium",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 128_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
        // Catalog-only — recognized when fetched via the API
        Record(id: "mistral-medium-3-1-25-08", displayName: "Mistral Medium 3.1",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 262_144,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "ministral-3-14b-25-12", displayName: "Ministral 3 14B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "ministral-3-8b-25-12", displayName: "Ministral 3 8B",
               capabilities: [.streaming, .toolCalling, .vision],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "ministral-3-3b-25-12", displayName: "Ministral 3 3B",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "devstral-2-25-12", displayName: "Devstral 2",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 256_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        Record(id: "codestral-25-08", displayName: "Codestral",
               capabilities: [.streaming, .toolCalling],
               contextWindow: 256_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        // Catalog-only — Z.ai GLM 5.3 (docs.mistral.ai/models/zai-glm-5-3, GA
        // 2026-09-28): third-party open-weight model hosted unmodified by Mistral.
        // Text model on this endpoint (no vision), 1M context / 128K max output,
        // function calling + structured outputs + prefix caching. Reasoning is
        // always-on upstream (Z.AI rejects `thinking.type: disabled`); Mistral
        // does not document a reasoning-effort field for this hosted model, so
        // reasoningConfig stays nil — Jin sends no reasoning params and exposes
        // no effort menu (same posture as mandatory-thinking models elsewhere).
        Record(id: "zai-glm-5-3", displayName: "Z.ai GLM 5.3",
               capabilities: [.streaming, .toolCalling, .reasoning, .promptCaching],
               contextWindow: 1_000_000,
               maxOutputTokens: 128_000,
               reasoningConfig: nil,
               isFullySupported: true, isSeeded: false),
        // Catalog-only alias: Mistral also publishes the `mistral-large-4-0`
        // spelling (model card versioned ID); same specs as `mistral-large-4`.
        Record(id: "mistral-large-4-0", displayName: "Mistral Large 4.0",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 1_000_000,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high,
                                                     supportedEfforts: [.none, .high]),
               isFullySupported: true, isSeeded: false),
        // Back-compat alias for the old short ID Jin previously seeded — keeps reasoning toggle
        // available for chats already pinned to this ID.
        Record(id: "mistral-medium-3.5", displayName: "Mistral Medium 3.5",
               capabilities: [.streaming, .toolCalling, .vision, .reasoning],
               contextWindow: 262_144,
               reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .high),
               isFullySupported: true, isSeeded: true),
    ]
}
