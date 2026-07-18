import Foundation

// MARK: - OpenAI declared features (catalog-layer SSoT)

extension ModelCatalog {
    /// Exact-ID feature declarations for native OpenAI / OpenAI WebSocket models.
    ///
    /// Used when a full `Record` is missing (legacy allowlist-only IDs) and to fill
    /// wire-policy fields (pro mode, verbosity, effort ladder) that sit beside
    /// `ModelCapability`. Prefer setting `Record.features` for new models; this
    /// table remains the migration home for OpenAI policy until every record
    /// embeds its features inline.
    static let openAIDeclaredFeaturesByID: [String: ModelFeatures] = [
        "gpt-4.1": .init(webSearch: true, codeExecution: true),
        "gpt-4.1-2025-04-14": .init(webSearch: true, codeExecution: true),
        "gpt-4o": .init(webSearch: true),
        "gpt-5": .init(webSearch: true, codeExecution: true),
        "gpt-5-2025-08-07": .init(webSearch: true, codeExecution: true),
        "gpt-5-mini": .init(webSearch: true, codeExecution: true),
        "gpt-5-mini-2025-08-07": .init(webSearch: true, codeExecution: true),
        "gpt-5-nano": .init(webSearch: true, codeExecution: true),
        "gpt-5-nano-2025-08-07": .init(webSearch: true, codeExecution: true),
        "gpt-5.2": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.2-2025-12-11": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.2-codex": .init(webSearch: true, openAIStyleExtremeEffort: true),
        "gpt-5.2-pro": .init(webSearch: true, openAIStyleExtremeEffort: true),
        "gpt-5.3-chat-latest": .init(webSearch: true),
        "gpt-5.3-codex": .init(webSearch: true, openAIStyleExtremeEffort: true),
        "gpt-5.3-codex-spark": .init(webSearch: true, openAIStyleExtremeEffort: true),
        "gpt-5.4": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.4-2026-03-05": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.4-image-2": .init(openAIStyleExtremeEffort: true),
        "gpt-5.4-mini": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.4-mini-2026-03-17": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.4-nano": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.4-nano-2026-03-17": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.4-pro": .init(
            webSearch: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.4-pro-2026-03-05": .init(
            webSearch: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.5": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.5-2026-04-23": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.5-pro": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.5-pro-2026-04-23": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true
        ),
        "gpt-5.6": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleProMode: true,
            openAIStyleReasoningContext: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true,
            openAIStyleMaxEffort: true
        ),
        "gpt-5.6-sol": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleProMode: true,
            openAIStyleReasoningContext: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true,
            openAIStyleMaxEffort: true
        ),
        "gpt-5.6-terra": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleProMode: true,
            openAIStyleReasoningContext: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true,
            openAIStyleMaxEffort: true
        ),
        "gpt-5.6-luna": .init(
            webSearch: true,
            codeExecution: true,
            openAIStyleProMode: true,
            openAIStyleReasoningContext: true,
            openAIStyleVerbosity: true,
            openAIStyleExtremeEffort: true,
            openAIStyleMaxEffort: true
        ),
        "gpt-5.6-sol-pro": .init(
            webSearch: true,
            openAIStyleExtremeEffort: true,
            openAIStyleMaxEffort: true
        ),
        "gpt-5.6-terra-pro": .init(
            webSearch: true,
            openAIStyleExtremeEffort: true,
            openAIStyleMaxEffort: true
        ),
        "gpt-5.6-luna-pro": .init(
            webSearch: true,
            openAIStyleExtremeEffort: true,
            openAIStyleMaxEffort: true
        ),
        "o3": .init(webSearch: true, codeExecution: true),
        "o4": .init(webSearch: true),
        "o4-mini": .init(webSearch: true, codeExecution: true),
    ]
}
