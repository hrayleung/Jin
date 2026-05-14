import Foundation

enum AnthropicModelLimits {
    static func supportsAdaptiveThinking(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return isOpus47(lower) || isOpus46(lower) || isSonnet46(lower)
    }

    static func supportsEffort(for modelID: String) -> Bool {
        // Effort works on Opus 4.7, Opus 4.6, Sonnet 4.6 (with adaptive thinking)
        // and Opus 4.5, Opus 4.1 (with budget_tokens thinking).
        // DeepSeek V4 exposes effort through Anthropic-compatible output_config.
        let lower = modelID.lowercased()
        return supportsAdaptiveThinking(for: lower)
            || isModelFamily(lower, prefix: "claude-opus-4-5")
            || isModelFamily(lower, prefix: "claude-opus-4-1")
            || isDeepSeekV4(lower)
    }

    static func supportsDeepSeekV4OutputConfigEffort(for modelID: String) -> Bool {
        isDeepSeekV4(modelID.lowercased())
    }

    static func supportsXHighEffort(for modelID: String) -> Bool {
        isOpus47(modelID.lowercased())
    }

    /// Fast mode (beta: research preview) is documented for the exact model IDs
    /// `claude-opus-4-7` and `claude-opus-4-6` only. Sending `speed: "fast"` to
    /// any other model — including date-suffixed snapshots of Opus 4.7/4.6 —
    /// returns an API error, and the request still bills at the fast-mode rate
    /// as extra usage, so we gate strictly on exact-match.
    static func supportsFastMode(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower == "claude-opus-4-7" || lower == "claude-opus-4-6"
    }

    static func supportsMaxEffort(for modelID: String) -> Bool {
        // Opus 4.7 supports both xhigh and max. Opus 4.6 supports max only.
        let lower = modelID.lowercased()
        return isOpus47(lower) || isOpus46(lower)
    }

    static func supportsSamplingParameters(for modelID: String) -> Bool {
        !isOpus47(modelID.lowercased())
    }

    static func requiresExplicitThinkingDisplay(for modelID: String) -> Bool {
        isOpus47(modelID.lowercased())
    }

    static func maxOutputTokens(for modelID: String) -> Int? {
        let lower = modelID.lowercased()

        if isOpus47(lower) || isOpus46(lower) {
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

    private static func isOpus47(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-opus-4-7")
    }

    private static func isOpus46(_ lowercasedModelID: String) -> Bool {
        isModelFamily(lowercasedModelID, prefix: "claude-opus-4-6")
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
