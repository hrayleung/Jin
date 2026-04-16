import Foundation

enum AnthropicModelLimits {
    static func supportsAdaptiveThinking(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return isOpus47(lower) || isOpus46(lower) || isSonnet46(lower)
    }

    static func supportsEffort(for modelID: String) -> Bool {
        // Effort works on Opus 4.7, Opus 4.6, Sonnet 4.6 (with adaptive thinking)
        // and Opus 4.5, Opus 4.1 (with budget_tokens thinking).
        let lower = modelID.lowercased()
        return supportsAdaptiveThinking(for: lower)
            || isModelFamily(lower, prefix: "claude-opus-4-5")
            || isModelFamily(lower, prefix: "claude-opus-4-1")
    }

    static func supportsXHighEffort(for modelID: String) -> Bool {
        isOpus47(modelID.lowercased())
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

    private static func isModelFamily(_ lowercasedModelID: String, prefix: String) -> Bool {
        lowercasedModelID == prefix || lowercasedModelID.hasPrefix("\(prefix)-")
    }
}
