import Foundation

enum AnthropicModelLimits {
    static func supportsAdaptiveThinking(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return isFableMythos5(lower) || isOpus5(lower) || isOpus48(lower) || isOpus47(lower)
            || isOpus46(lower) || isSonnet5(lower) || isSonnet46(lower)
    }

    static func supportsEffort(for modelID: String) -> Bool {
        // Effort works on Opus 5, Opus 4.8, Opus 4.7, Opus 4.6, Sonnet 5, Sonnet 4.6 (with adaptive
        // thinking) and Opus 4.5, Opus 4.1 (with budget_tokens thinking).
        // DeepSeek V4 exposes effort through Anthropic-compatible output_config.
        let lower = modelID.lowercased()
        return supportsAdaptiveThinking(for: lower)
            || isModelFamily(lower, prefix: "claude-opus-4-5")
            || isModelFamily(lower, prefix: "claude-opus-4-1")
            || isDeepSeekV4(lower)
    }

    /// Models where OMITTING `thinking` does not disable it, but an explicit
    /// `{type: "disabled"}` is accepted. Claude Opus 5 is in this set. Claude Sonnet 5
    /// is not: the model card documents adaptive thinking as always on (same as Fable 5),
    /// so `thinking: {type: "disabled"}` must not be sent — omit the field instead.
    /// Opus 5 additionally caps the effort it accepts alongside a disabled thinking
    /// block — see `disabledThinkingRequiresEffortAtMostHigh`.
    static func requiresExplicitThinkingDisabled(for modelID: String) -> Bool {
        isOpus5(modelID.lowercased())
    }

    /// Opus 5 accepts `thinking: {type: "disabled"}` only at effort `high` or below;
    /// pairing it with `xhigh`/`max` returns a 400. The API validates this per request,
    /// so every call site that can emit both fields has to clamp, not just the first.
    static func disabledThinkingRequiresEffortAtMostHigh(for modelID: String) -> Bool {
        isOpus5(modelID.lowercased())
    }

    static func supportsDeepSeekV4OutputConfigEffort(for modelID: String) -> Bool {
        isDeepSeekV4(modelID.lowercased())
    }

    static func supportsXHighEffort(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return isFableMythos5(lower) || isOpus5(lower) || isOpus48(lower) || isOpus47(lower)
            || isSonnet5(lower)
    }

    /// Fast mode (beta: research preview) is documented for the exact model IDs
    /// `claude-opus-5` and `claude-opus-4-8` only. Opus 4.7 fast mode has since been
    /// removed upstream (`speed: "fast"` on 4.7 now errors) and the retired
    /// `claude-opus-4-6-fast` route silently falls back to standard Opus 4.6, so both
    /// are gated off here. Sending `speed: "fast"` to any other model — including
    /// date-suffixed snapshots of Opus 5/4.8 — returns an API error, and the request
    /// still bills at the fast-mode rate as extra usage, so we gate strictly on
    /// exact-match.
    static func supportsFastMode(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower == "claude-opus-5" || lower == "claude-opus-4-8"
    }

    static func supportsMaxEffort(for modelID: String) -> Bool {
        // Fable/Mythos 5, Opus 5, Opus 4.8/4.7, and Sonnet 5 support both xhigh and max.
        // Opus 4.6 supports max only.
        let lower = modelID.lowercased()
        return isFableMythos5(lower) || isOpus5(lower) || isOpus48(lower) || isOpus47(lower)
            || isOpus46(lower) || isSonnet5(lower)
    }

    static func supportsSamplingParameters(for modelID: String) -> Bool {
        // Sampling params (temperature/top_p/top_k) are removed on Fable/Mythos 5, Opus 5 and
        // Opus 4.8/4.7. On Sonnet 5, only non-default values 400 (omitting/defaulting is
        // accepted) — but Jin only ever sends a value when the user explicitly set one in the
        // UI, which is never the API default, so treat Sonnet 5 the same as the other
        // adaptive-thinking models: strip it.
        let lower = modelID.lowercased()
        return !(isFableMythos5(lower) || isOpus5(lower) || isOpus48(lower) || isOpus47(lower)
            || isSonnet5(lower))
    }

    static func requiresExplicitThinkingDisplay(for modelID: String) -> Bool {
        // Raw thinking is never returned on Fable/Mythos 5, Opus 5, Opus 4.8/4.7, and Sonnet 5;
        // `thinking.display` defaults to "omitted" on all of them (a silent change from Sonnet
        // 4.6, which defaulted to "summarized"), so we opt in to "summarized" to surface readable
        // reasoning.
        let lower = modelID.lowercased()
        return isFableMythos5(lower) || isOpus5(lower) || isOpus48(lower) || isOpus47(lower)
            || isSonnet5(lower)
    }

    static func maxOutputTokens(for modelID: String) -> Int? {
        let lower = modelID.lowercased()

        if isFableMythos5(lower) || isOpus5(lower) || isOpus48(lower) || isOpus47(lower)
            || isOpus46(lower) || isSonnet5(lower) {
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

        // Kimi K2.7 Code (Kimi for Coding provider): 262,144 max output per the
        // model catalog. K3's max output is undocumented, so it intentionally
        // falls through to the resolver fallback.
        if lower == "kimi-for-coding" || lower == "kimi-for-coding-highspeed" {
            return 262_144
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

    /// The Fable/Mythos 5 generation (`claude-fable-5`, `claude-fable-5-1`,
    /// `claude-mythos-5`, `claude-mythos-5-1`). Mythos shares Fable's exact API
    /// surface (adaptive-thinking-only, no sampling params, 128k output) without the
    /// safety classifiers. Note: the older invitation-only `claude-mythos-preview` is a
    /// different model and is intentionally NOT matched here.
    static func isFableMythos5(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-fable-5")
            || isModelFamily(lowercasedModelID, prefix: "claude-mythos-5")
    }

    /// Claude Opus 5. Same adaptive-thinking-only surface as Opus 4.8 (no `budget_tokens`,
    /// no sampling params, 1M context / 128k output, full `low`…`max` effort ladder), with
    /// two behavioural flips: thinking is ON when `thinking` is omitted, and an explicit
    /// `{type: "disabled"}` is only accepted at effort `high` or below.
    static func isOpus5(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-opus-5")
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
        let bare = bareAnthropicModelID(lowercasedModelID)
        return bare == prefix || bare.hasPrefix("\(prefix)-")
    }

    /// OpenRouter / Vercel / Cloudflare compound IDs (`anthropic/claude-sonnet-5`).
    /// Do not strip arbitrary leading junk — `beta-claude-opus-4-6-variant` must not
    /// match the Opus 4.6 family.
    private static func bareAnthropicModelID(_ lowercasedModelID: String) -> String {
        if lowercasedModelID.hasPrefix("anthropic/") {
            return String(lowercasedModelID.dropFirst("anthropic/".count))
        }
        return lowercasedModelID
    }
}
