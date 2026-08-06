import Foundation

/// Provider reasoning block (e.g., OpenAI reasoning text; Anthropic thinking block with signature)
struct ThinkingBlock: Codable, Sendable {
    let text: String
    let signature: String?
    /// The provider type that originated this thinking block (e.g. "anthropic", "gemini").
    /// Used to filter out foreign thinking blocks when sending to a specific provider.
    let provider: String?

    init(text: String, signature: String? = nil, provider: String? = nil) {
        self.text = text
        self.signature = signature
        self.provider = provider
    }
}

/// Provider-redacted / encrypted reasoning block.
///
/// - Anthropic: `data` is the opaque `redacted_thinking` blob.
/// - Meta Muse Spark (Responses): `data` is `encrypted_content` for stateless CoT
///   replay; optional `id` is the `rs_…` reasoning item id from the prior response.
struct RedactedThinkingBlock: Codable, Sendable {
    let data: String
    /// The provider type that originated this block.
    let provider: String?
    /// Optional provider item id (Meta Responses reasoning item `rs_…`).
    let id: String?

    init(data: String, provider: String? = nil, id: String? = nil) {
        self.data = data
        self.provider = provider
        self.id = id
    }
}
