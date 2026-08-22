import Foundation

/// Router-specific wire constraints that the generic OpenAI Responses builder cannot
/// infer from the model ID alone.
///
/// Router translates one Responses payload onto whichever upstream serves the model,
/// and Anthropic's own rules leak through that translation. Both rules below were
/// reproduced against the live gateway on 2026-08-22.
enum RouterRequestSupport {
    /// Router serves Anthropic under bare `claude-*` slugs (`claude-opus-5`,
    /// `claude-haiku-4-5`, …). Every other backend it fronts is either an OpenAI
    /// slug, an xAI `grok-*` slug, or a Fireworks `accounts/…` path.
    static func isAnthropicRoutedModelID(_ modelID: String) -> Bool {
        modelID.lowercased().hasPrefix("claude-")
    }

    /// With reasoning enabled, an Anthropic-routed request whose `max_output_tokens`
    /// is too small is rejected outright:
    ///
    ///     400 invalid_request — "max_output_tokens is too small to enable reasoning:
    ///     Anthropic requires a thinking budget of at least 1024 tokens strictly
    ///     below max_output_tokens."
    ///
    /// The floor is a constant, not effort-scaled: 1025 succeeds at every effort, and
    /// `xhigh` / `max` need no more than `low` does — Router sizes the budget to fit.
    static let minimumMaxOutputTokensWithReasoning = 1025

    /// Whether this request needs the Anthropic thinking-budget headroom.
    static func requiresAnthropicThinkingHeadroom(
        providerType: ProviderType?,
        modelID: String,
        reasoningEnabled: Bool
    ) -> Bool {
        providerType == .router && reasoningEnabled && isAnthropicRoutedModelID(modelID)
    }

    /// Anthropic rejects any explicit temperature other than 1 while thinking is on:
    ///
    ///     400 — "`temperature` may only be set to 1 when thinking is enabled."
    ///
    /// Jin's general Responses gate only strips sampling for `gpt-5*`, so without this
    /// a Router `claude-*` send with a non-default temperature fails every time.
    static func suppressesSamplingParameters(
        providerType: ProviderType?,
        modelID: String,
        reasoningEnabled: Bool
    ) -> Bool {
        requiresAnthropicThinkingHeadroom(
            providerType: providerType,
            modelID: modelID,
            reasoningEnabled: reasoningEnabled
        )
    }
}
