import Foundation

// MARK: - Anthropic declared features (catalog-layer SSoT)

extension ModelCatalog {
    /// Exact-ID feature declarations for native Anthropic models.
    ///
    /// Code execution and dynamic web-search filtering use documented allowlists.
    /// General web search is available on current Claude IDs (including Fable/Mythos 5).
    static let anthropicDeclaredFeaturesByID: [String: ModelFeatures] = [
        // Legacy / unlisted IDs keep web search but not code execution (docs allowlist, 2026-07).
        "claude-3-5-haiku-latest": .init(webSearch: true, codeExecution: false),
        "claude-3-7-sonnet-20250219": .init(webSearch: true, codeExecution: false),
        "claude-fable-5": .init(
            webSearch: true,
            codeExecution: true,
            webSearchDynamicFiltering: true
        ),
        "claude-mythos-5": .init(
            webSearch: true,
            codeExecution: true,
            webSearchDynamicFiltering: true
        ),
        "claude-haiku-4": .init(webSearch: true, codeExecution: false),
        "claude-haiku-4-5-20251001": .init(webSearch: true, codeExecution: true),
        "claude-opus-4": .init(webSearch: true, codeExecution: false),
        "claude-opus-4-1-20250805": .init(webSearch: true, codeExecution: true),
        // Dated Opus/Sonnet 4 snapshots are not on the current code-execution allowlist.
        "claude-opus-4-20250514": .init(webSearch: true, codeExecution: false),
        "claude-opus-4-5-20251101": .init(webSearch: true, codeExecution: true),
        "claude-opus-4-6": .init(
            webSearch: true,
            codeExecution: true,
            webSearchDynamicFiltering: true
        ),
        "claude-opus-4-7": .init(
            webSearch: true,
            codeExecution: true,
            webSearchDynamicFiltering: true
        ),
        "claude-opus-4-8": .init(
            webSearch: true,
            codeExecution: true,
            webSearchDynamicFiltering: true
        ),
        "claude-sonnet-4": .init(webSearch: true, codeExecution: false),
        "claude-sonnet-4-20250514": .init(webSearch: true, codeExecution: false),
        "claude-sonnet-4-5-20250929": .init(webSearch: true, codeExecution: true),
        "claude-sonnet-4-6": .init(
            webSearch: true,
            codeExecution: true,
            webSearchDynamicFiltering: true
        ),
        "claude-sonnet-5": .init(
            webSearch: true,
            codeExecution: true,
            webSearchDynamicFiltering: true
        ),
    ]
}
