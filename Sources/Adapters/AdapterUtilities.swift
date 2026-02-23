import Foundation

// MARK: - Shared Adapter Utilities

/// Returns a trimmed, non-empty string or nil. Used across adapters to normalize
/// optional string fields (cache keys, conversation IDs, etc.) before sending to providers.
func normalizedTrimmedString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Constructs a URL from a string, throwing `LLMError.invalidRequest` instead of crashing
/// on malformed input. Use this instead of `URL(string:)!` everywhere a provider base URL
/// or user-configurable endpoint is interpolated.
func validatedURL(_ string: String) throws -> URL {
    guard let url = URL(string: string) else {
        throw LLMError.invalidRequest(message: "Invalid URL: \(string)")
    }
    return url
}
