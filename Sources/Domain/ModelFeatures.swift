import Foundation

/// Declarative wire-level / product features that sit alongside `ModelCapability`.
///
/// Capabilities describe broad modalities (vision, reasoning, code execution, …).
/// Features capture UI/API policy that used to live only in `ModelCapabilityRegistry`
/// allowlists (web search, maps, effort ladders, request shape, …).
///
/// During the dual-read migration:
/// - `nil` optional fields mean "not declared on the catalog record yet — fall back to registry"
/// - non-`nil` values are the single source of truth for that model
struct ModelFeatures: Sendable, Equatable {
    /// Native provider web search / Google Search grounding.
    var webSearch: Bool?
    /// Google Maps grounding (Gemini / Vertex).
    var googleMaps: Bool?
    /// Native code execution / code interpreter.
    /// Prefer setting this explicitly; otherwise `ModelCapability.codeExecution` is the catalog signal.
    var codeExecution: Bool?
    /// Anthropic `web_search_20260209` dynamic filtering.
    var webSearchDynamicFiltering: Bool?
    /// Whether the user can turn reasoning off (false for always-on models).
    var reasoningCanDisable: Bool?
    /// Request wire shape override (chat completions vs Responses vs Anthropic vs Gemini).
    var requestShape: ModelRequestShape?
    /// Supported reasoning effort ladder when it differs from shape defaults.
    var effortLadder: [ReasoningEffort]?
    /// OpenAI Responses `reasoning.mode = "pro"`.
    var openAIStyleProMode: Bool?
    /// OpenAI Responses `reasoning.context`.
    var openAIStyleReasoningContext: Bool?
    /// OpenAI Responses `text.verbosity`.
    var openAIStyleVerbosity: Bool?

    /// OpenAI-style effort ladder includes `xhigh` (GPT-5.2+).
    var openAIStyleExtremeEffort: Bool?
    /// OpenAI-style effort ladder includes `max` (GPT-5.6 family).
    var openAIStyleMaxEffort: Bool?

    static let unspecified = ModelFeatures()

    init(
        webSearch: Bool? = nil,
        googleMaps: Bool? = nil,
        codeExecution: Bool? = nil,
        webSearchDynamicFiltering: Bool? = nil,
        reasoningCanDisable: Bool? = nil,
        requestShape: ModelRequestShape? = nil,
        effortLadder: [ReasoningEffort]? = nil,
        openAIStyleProMode: Bool? = nil,
        openAIStyleReasoningContext: Bool? = nil,
        openAIStyleVerbosity: Bool? = nil,
        openAIStyleExtremeEffort: Bool? = nil,
        openAIStyleMaxEffort: Bool? = nil
    ) {
        self.webSearch = webSearch
        self.googleMaps = googleMaps
        self.codeExecution = codeExecution
        self.webSearchDynamicFiltering = webSearchDynamicFiltering
        self.reasoningCanDisable = reasoningCanDisable
        self.requestShape = requestShape
        self.effortLadder = effortLadder
        self.openAIStyleProMode = openAIStyleProMode
        self.openAIStyleReasoningContext = openAIStyleReasoningContext
        self.openAIStyleVerbosity = openAIStyleVerbosity
        self.openAIStyleExtremeEffort = openAIStyleExtremeEffort
        self.openAIStyleMaxEffort = openAIStyleMaxEffort
    }

    var isUnspecified: Bool {
        webSearch == nil
            && googleMaps == nil
            && codeExecution == nil
            && webSearchDynamicFiltering == nil
            && reasoningCanDisable == nil
            && requestShape == nil
            && effortLadder == nil
            && openAIStyleProMode == nil
            && openAIStyleReasoningContext == nil
            && openAIStyleVerbosity == nil
            && openAIStyleExtremeEffort == nil
            && openAIStyleMaxEffort == nil
    }

    /// Prefer non-nil fields from `self`; fill gaps from `fallback`.
    func filling(from fallback: ModelFeatures) -> ModelFeatures {
        ModelFeatures(
            webSearch: webSearch ?? fallback.webSearch,
            googleMaps: googleMaps ?? fallback.googleMaps,
            codeExecution: codeExecution ?? fallback.codeExecution,
            webSearchDynamicFiltering: webSearchDynamicFiltering ?? fallback.webSearchDynamicFiltering,
            reasoningCanDisable: reasoningCanDisable ?? fallback.reasoningCanDisable,
            requestShape: requestShape ?? fallback.requestShape,
            effortLadder: effortLadder ?? fallback.effortLadder,
            openAIStyleProMode: openAIStyleProMode ?? fallback.openAIStyleProMode,
            openAIStyleReasoningContext: openAIStyleReasoningContext ?? fallback.openAIStyleReasoningContext,
            openAIStyleVerbosity: openAIStyleVerbosity ?? fallback.openAIStyleVerbosity,
            openAIStyleExtremeEffort: openAIStyleExtremeEffort ?? fallback.openAIStyleExtremeEffort,
            openAIStyleMaxEffort: openAIStyleMaxEffort ?? fallback.openAIStyleMaxEffort
        )
    }

    /// Effective code-execution support when the catalog has spoken (feature flag or capability bit).
    func resolvedCodeExecution(capabilities: ModelCapability) -> Bool? {
        if let codeExecution {
            return codeExecution
        }
        if capabilities.contains(.codeExecution) {
            return true
        }
        return nil
    }
}
