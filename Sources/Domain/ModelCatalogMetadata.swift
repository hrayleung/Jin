import Foundation

/// Optional provider-returned model catalog metadata.
/// This is informational (for example upgrade nudges or limited-availability notes),
/// and should not be treated as manual user overrides.
struct ModelCatalogMetadata: Codable, Equatable {
    var availabilityMessage: String?
    var upgradeTargetModelID: String?
    var upgradeMessage: String?
    /// Per-model request host, used when a provider addresses each model at its
    /// own URL (Modal Auto Endpoints: `https://<host>/v1`).
    var requestBaseURL: String?
    /// Hugging Face repo ID (or other wire `model` value) when it differs from
    /// `ModelInfo.id`, or after an Auto Endpoint row is promoted so `id` and
    /// this field match.
    var upstreamModelID: String?

    init(
        availabilityMessage: String? = nil,
        upgradeTargetModelID: String? = nil,
        upgradeMessage: String? = nil,
        requestBaseURL: String? = nil,
        upstreamModelID: String? = nil
    ) {
        self.availabilityMessage = availabilityMessage
        self.upgradeTargetModelID = upgradeTargetModelID
        self.upgradeMessage = upgradeMessage
        self.requestBaseURL = requestBaseURL
        self.upstreamModelID = upstreamModelID
    }

    var isEmpty: Bool {
        availabilityMessage?.trimmedNonEmpty == nil
            && upgradeTargetModelID?.trimmedNonEmpty == nil
            && upgradeMessage?.trimmedNonEmpty == nil
            && requestBaseURL?.trimmedNonEmpty == nil
            && upstreamModelID?.trimmedNonEmpty == nil
    }
}
