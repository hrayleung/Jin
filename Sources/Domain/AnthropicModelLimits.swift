import Foundation

enum AnthropicModelLimits {
    static func supportsAdaptiveThinking(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return isFableMythos5(lower) || isOpus48(lower) || isOpus47(lower) || isOpus46(lower)
            || isSonnet5(lower) || isSonnet46(lower)
    }

    static func supportsEffort(for modelID: String) -> Bool {
        // Effort works on Opus 4.8, Opus 4.7, Opus 4.6, Sonnet 5, Sonnet 4.6 (with adaptive thinking)
        // and Opus 4.5, Opus 4.1 (with budget_tokens thinking).
        // DeepSeek V4 exposes effort through Anthropic-compatible output_config.
        let lower = modelID.lowercased()
        return supportsAdaptiveThinking(for: lower)
            || isModelFamily(lower, prefix: "claude-opus-4-5")
            || isModelFamily(lower, prefix: "claude-opus-4-1")
            || isDeepSeekV4(lower)
    }

    /// Sonnet 5 is the only adaptive-thinking Anthropic model where OMITTING `thinking`
    /// does not disable it — Anthropic's migration guide: "on Claude Sonnet 5, omitting
    /// runs adaptive; on Opus 4.7/4.8, omitting runs without thinking." So disabling
    /// reasoning on Sonnet 5 requires sending `thinking: {type: "disabled"}` explicitly
    /// (which Sonnet 5 accepts, unlike Fable 5, where an explicit "disabled" 400s).
    static func requiresExplicitThinkingDisabled(for modelID: String) -> Bool {
        isSonnet5(modelID.lowercased())
    }

    static func supportsDeepSeekV4OutputConfigEffort(for modelID: String) -> Bool {
        isDeepSeekV4(modelID.lowercased())
    }

    static func supportsXHighEffort(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return isFableMythos5(lower) || isOpus48(lower) || isOpus47(lower) || isSonnet5(lower)
    }

    /// Fast mode (beta: research preview) is documented for the exact model IDs
    /// `claude-opus-4-8`, `claude-opus-4-7` and `claude-opus-4-6` only. Sending
    /// `speed: "fast"` to any other model — including date-suffixed snapshots of
    /// Opus 4.8/4.7/4.6 — returns an API error, and the request still bills at
    /// the fast-mode rate as extra usage, so we gate strictly on exact-match.
    static func supportsFastMode(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower == "claude-opus-4-8" || lower == "claude-opus-4-7" || lower == "claude-opus-4-6"
    }

    static func supportsMaxEffort(for modelID: String) -> Bool {
        // Fable/Mythos 5, Opus 4.8/4.7, and Sonnet 5 support both xhigh and max. Opus 4.6 supports max only.
        let lower = modelID.lowercased()
        return isFableMythos5(lower) || isOpus48(lower) || isOpus47(lower) || isOpus46(lower) || isSonnet5(lower)
    }

    static func supportsSamplingParameters(for modelID: String) -> Bool {
        // Sampling params (temperature/top_p/top_k) are removed on Fable/Mythos 5 and Opus 4.8/4.7.
        // On Sonnet 5, only non-default values 400 (omitting/defaulting is accepted) — but Jin only
        // ever sends a value when the user explicitly set one in the UI, which is never the API
        // default, so treat Sonnet 5 the same as the other adaptive-thinking models: strip it.
        let lower = modelID.lowercased()
        return !(isFableMythos5(lower) || isOpus48(lower) || isOpus47(lower) || isSonnet5(lower))
    }

    static func requiresExplicitThinkingDisplay(for modelID: String) -> Bool {
        // Raw thinking is never returned on Fable/Mythos 5, Opus 4.8/4.7, and Sonnet 5;
        // `thinking.display` defaults to "omitted" on all of them (a silent change from Sonnet
        // 4.6, which defaulted to "summarized"), so we opt in to "summarized" to surface readable
        // reasoning.
        let lower = modelID.lowercased()
        return isFableMythos5(lower) || isOpus48(lower) || isOpus47(lower) || isSonnet5(lower)
    }

    static func maxOutputTokens(for modelID: String) -> Int? {
        let lower = modelID.lowercased()

        if isFableMythos5(lower) || isOpus48(lower) || isOpus47(lower) || isOpus46(lower) || isSonnet5(lower) {
            return 128_000
        }

        if lower == "mimo-v2.5-pro"
            || lower == "mimo-v2.5"
            || lower == "mimo-v2-pro"
            || lower == "mimo-v2-omni" {
            return 131_072
        }

        if lower == "mimo-v2-flash" {
            return 65_536
        }

        if isSonnet46(lower)
            || isModelFamily(lower, prefix: "claude-opus-4-5")
            || isModelFamily(lower, prefix: "claude-sonnet-4-5")
            || isModelFamily(lower, prefix: "claude-haiku-4-5") {
            return 64_000
        }

        return nil
    }

    static func resolvedMaxTokens(requested: Int?, for modelID: String, fallback: Int = 4096) -> Int {
        let modelMax = maxOutputTokens(for: modelID)
        let normalizedRequested = requested.flatMap { $0 > 0 ? $0 : nil }

        var resolved = normalizedRequested ?? modelMax ?? fallback
        if let modelMax {
            resolved = min(resolved, modelMax)
        }

        return max(1, resolved)
    }

    /// The Fable/Mythos 5 generation (`claude-fable-5`, `claude-mythos-5`). Mythos 5
    /// shares Fable 5's exact API surface (adaptive-thinking-only, no sampling params,
    /// 128k output) without the safety classifiers. Note: the older invitation-only
    /// `claude-mythos-preview` is a different model and is intentionally NOT matched here.
    static func isFableMythos5(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-fable-5")
            || isModelFamily(lowercasedModelID, prefix: "claude-mythos-5")
    }

    private static func isOpus48(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-opus-4-8")
    }

    private static func isOpus47(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-opus-4-7")
    }

    private static func isOpus46(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-opus-4-6")
    }

    static func isSonnet5(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-sonnet-5")
    }

    private static func isSonnet46(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-sonnet-4-6")
    }

    private static func isDeepSeekV4(_ lowercasedModelID: String) -> Bool {
        lowercasedModelID == "deepseek-v4-flash" || lowercasedModelID == "deepseek-v4-pro"
    }

    private static func isModelFamily(_ lowercasedModelID: String, prefix: String) -> Bool {
        lowercasedModelID == prefix || lowercasedModelID.hasPrefix("\(prefix)-")
    }
}
