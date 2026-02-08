import Foundation

enum AnthropicModelLimits {
    static func supportsAdaptiveThinking(for modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return lower == "claude-opus-4-6" || lower.contains("claude-opus-4-6-")
    }

    static func supportsEffort(for modelID: String) -> Bool {
        // Anthropic effort is the new thinking control for Opus 4.6.
        supportsAdaptiveThinking(for: modelID)
    }

    static func supportsMaxEffort(for modelID: String) -> Bool {
        supportsAdaptiveThinking(for: modelID)
    }

    static func maxOutputTokens(for modelID: String) -> Int? {
        let lower = modelID.lowercased()

        if lower == "claude-opus-4-6" || lower.contains("claude-opus-4-6-") {
            return 128_000
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
}
