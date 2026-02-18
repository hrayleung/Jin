import Foundation

enum AnthropicModelLimits {
    static func supportsAdaptiveThinking(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return isOpus46(lower) || isSonnet46(lower)
    }

    static func supportsEffort(for modelID: String) -> Bool {
        // Claude 4.6 models use effort with adaptive thinking.
        supportsAdaptiveThinking(for: modelID)
    }

    static func supportsMaxEffort(for modelID: String) -> Bool {
        // Sonnet 4.6 supports low/medium/high, but not max.
        isOpus46(modelID.lowercased())
    }

    static func maxOutputTokens(for modelID: String) -> Int? {
        let lower = modelID.lowercased()

        if isOpus46(lower) {
            return 128_000
        }

        if isSonnet46(lower) {
            return 64_000
        }

        if lower == "claude-opus-4-5" || lower.contains("claude-opus-4-5-") {
            return 64_000
        }

        if lower == "claude-sonnet-4-5" || lower.contains("claude-sonnet-4-5-") {
            return 64_000
        }

        if lower == "claude-haiku-4-5" || lower.contains("claude-haiku-4-5-") {
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

    private static func isOpus46(_ lowercasedModelID: String) -> Bool {
        lowercasedModelID == "claude-opus-4-6" || lowercasedModelID.contains("claude-opus-4-6-")
    }

    private static func isSonnet46(_ lowercasedModelID: String) -> Bool {
        lowercasedModelID == "claude-sonnet-4-6" || lowercasedModelID.contains("claude-sonnet-4-6-")
    }
}
