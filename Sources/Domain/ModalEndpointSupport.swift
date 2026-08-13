import Foundation

/// Shared API regions for `https://inference.<region>.modal.direct/v1`.
///
/// From modal.com/docs/guide/endpoints (routing-region list).
enum ModalSharedRegion: String, CaseIterable, Identifiable, Hashable {
    case usWest = "us-west"
    case usEast = "us-east"
    case caCentral = "ca-central"
    case euWest = "eu-west"
    case apSouth = "ap-south"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usWest: return "US West"
        case .usEast: return "US East"
        case .caCentral: return "Canada Central"
        case .euWest: return "EU West"
        case .apSouth: return "Asia Pacific South"
        }
    }

    var baseURL: String {
        "https://inference.\(rawValue).modal.direct/v1"
    }

    /// Matches a stored provider base URL, with or without `/v1`.
    static func matching(baseURL: String) -> ModalSharedRegion? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return allCases.first { region in
            let canonical = region.baseURL.lowercased()
            let hostOnly = canonical.hasSuffix("/v1")
                ? String(canonical.dropLast(3)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : canonical
            return trimmed == canonical || trimmed == hostOnly
        }
    }
}

/// Parsing and display helpers for Modal Auto Endpoint URLs / hostnames.
///
/// Official calling shape (modal.com/docs/guide/endpoints): each
/// `modal endpoint create --model …` deployment has its own URL. Chat goes to
/// `POST <endpoint-url>/v1/chat/completions` with `model` set to the Hugging
/// Face repo ID. Region is chosen when the endpoint is created, not in the client.
enum ModalEndpointSupport {
    static let hostSuffix = ".modal.direct"

    /// The Shared API host itself (`inference.<region>.modal.direct`) is not an
    /// Auto Endpoint and must not be added as a model.
    static func isSharedAPIHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower.hasPrefix("inference.") && lower.hasSuffix(hostSuffix)
    }

    static func isAutoEndpointHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower.hasSuffix(hostSuffix) && !isSharedAPIHost(lower) && lower != hostSuffix
    }

    /// Extracts an Auto Endpoint hostname from a pasted URL, host, or model ID.
    /// Returns nil for Shared API hosts, HF repo IDs, and anything that is not
    /// `*.modal.direct`.
    static func autoEndpointHost(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let host: String
        if let parsed = URL(string: trimmed), parsed.scheme != nil, let urlHost = parsed.host, !urlHost.isEmpty {
            host = urlHost
        } else if trimmed.contains("://") {
            return nil
        } else {
            let withoutPath = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? trimmed
            host = withoutPath
        }

        let normalized = host.lowercased()
        guard isAutoEndpointHost(normalized) else { return nil }
        return normalized
    }

    static func isAutoEndpointModelID(_ modelID: String) -> Bool {
        autoEndpointHost(from: modelID) != nil
    }

    /// True when this row is a dedicated Auto Endpoint, even after its stored
    /// `id` has been rewritten to the Hugging Face repo ID.
    static func isAutoEndpointModel(_ model: ModelInfo) -> Bool {
        if isAutoEndpointModelID(model.id) { return true }
        if let base = model.catalogMetadata?.requestBaseURL,
           autoEndpointHost(from: base) != nil {
            return true
        }
        return false
    }

    /// ID used for catalog / capability lookup. Endpoints use the Hugging Face
    /// repo ID when we know it, not the workspace hostname.
    static func catalogModelID(for model: ModelInfo) -> String {
        model.catalogMetadata?.upstreamModelID?.trimmedNonEmpty ?? model.id
    }

    /// ID shown under the display name. The endpoint hostname is an address,
    /// not a model ID — people should see `Qwen/Qwen3.8-2.4T-A95B`.
    static func userFacingModelID(for model: ModelInfo) -> String? {
        if let upstream = model.catalogMetadata?.upstreamModelID?.trimmedNonEmpty {
            return upstream
        }
        if isAutoEndpointModelID(model.id) {
            return nil
        }
        return model.id
    }

    /// Two rows point at the same Modal deployment (same host), regardless of
    /// whether `id` is still the hostname or has been promoted to the repo ID.
    static func isSameDeployment(_ lhs: ModelInfo, _ rhs: ModelInfo) -> Bool {
        guard let left = deploymentHost(for: lhs), let right = deploymentHost(for: rhs) else {
            return false
        }
        return left == right
    }

    static func deploymentHost(for model: ModelInfo) -> String? {
        if let host = autoEndpointHost(from: model.id) { return host }
        if let base = model.catalogMetadata?.requestBaseURL {
            return autoEndpointHost(from: base)
        }
        return nil
    }

    /// Finds a configured model by stored id, Hugging Face id, or endpoint host.
    /// Conversations may still mention a hostname after the row's `id` was
    /// promoted to the repo ID.
    static func configuredModel(in models: [ModelInfo], matching modelID: String) -> ModelInfo? {
        if let exact = models.first(where: { $0.id == modelID }) {
            return exact
        }

        let target = modelID.lowercased()
        if let ci = models.first(where: { $0.id.lowercased() == target }) {
            return ci
        }
        if let byUpstream = models.first(where: {
            $0.catalogMetadata?.upstreamModelID?.lowercased() == target
        }) {
            return byUpstream
        }

        guard let host = autoEndpointHost(from: modelID) else { return nil }
        return models.first { deploymentHost(for: $0) == host }
    }

    /// Prefer the Hugging Face repo as `ModelInfo.id` once we know it. The
    /// hostname stays on `requestBaseURL` for routing.
    static func promotedIdentity(for model: ModelInfo) -> ModelInfo {
        let withMetadata = applyEndpointMetadataIfNeeded(to: model)
        guard isAutoEndpointModelID(withMetadata.id),
              let upstream = withMetadata.catalogMetadata?.upstreamModelID?.trimmedNonEmpty,
              upstream != withMetadata.id
        else {
            return withMetadata
        }
        return replacingIdentity(withMetadata, id: upstream)
    }

    static func promoteIdentities(in models: [ModelInfo]) -> [ModelInfo] {
        var usedIDs = Set<String>()
        return models.map { model in
            let promoted = promotedIdentity(for: model)
            if usedIDs.contains(promoted.id) {
                let fallback = applyEndpointMetadataIfNeeded(to: model)
                usedIDs.insert(fallback.id)
                return fallback
            }
            usedIDs.insert(promoted.id)
            return promoted
        }
    }

    /// First DNS label (`workspace--app-server.us-west.modal.direct` →
    /// `workspace--app-server`). Nil for Shared API models.
    static func displayName(forModelID modelID: String) -> String? {
        guard let host = autoEndpointHost(from: modelID) else { return nil }
        let label = String(host.prefix(while: { $0 != "." }))
        return label.isEmpty ? nil : label
    }

    /// If the paste is an Auto Endpoint URL/host, return the hostname; otherwise
    /// the trimmed original (HF repo IDs stay intact).
    static func normalizedModelID(from raw: String) -> String {
        autoEndpointHost(from: raw) ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func chatBaseURL(forHost host: String) -> String {
        "https://\(host)/v1"
    }

    static func normalizedChatBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if withoutSlash.lowercased().hasSuffix("/v1") {
            return withoutSlash
        }
        return "\(withoutSlash)/v1"
    }

    static func modelInfo(
        fromPasted raw: String,
        nickname: String?,
        upstreamModelID: String? = nil
    ) -> ModelInfo? {
        guard let host = autoEndpointHost(from: raw) else { return nil }
        let wireID = upstreamModelID?.trimmedNonEmpty
        let identityID = wireID ?? host
        let catalog = ModelCatalog.modelInfo(
            for: identityID,
            provider: .modal,
            name: nil
        )
        let name = nickname?.trimmedNonEmpty
            ?? (wireID == nil ? nil : catalog.name)
            ?? displayName(forModelID: host)
            ?? host
        return ModelInfo(
            id: identityID,
            name: name,
            capabilities: catalog.capabilities,
            contextWindow: catalog.contextWindow,
            maxOutputTokens: catalog.maxOutputTokens,
            reasoningConfig: catalog.reasoningConfig,
            catalogMetadata: ModelCatalogMetadata(
                requestBaseURL: chatBaseURL(forHost: host),
                upstreamModelID: wireID
            )
        )
    }

    static func applyEndpointMetadataIfNeeded(to model: ModelInfo) -> ModelInfo {
        guard let host = autoEndpointHost(from: model.id) else { return model }
        var updated = model
        var metadata = updated.catalogMetadata ?? ModelCatalogMetadata()
        if metadata.requestBaseURL?.trimmedNonEmpty == nil {
            metadata.requestBaseURL = chatBaseURL(forHost: host)
        }
        updated.catalogMetadata = metadata
        return updated
    }

    /// Resolves the request host and wire `model` for a configured Modal model.
    static func requestRoute(
        modelID: String,
        configured: ModelInfo?,
        providerBaseURL: String
    ) -> (baseURL: String, wireModelID: String) {
        if let requestBaseURL = configured?.catalogMetadata?.requestBaseURL?.trimmedNonEmpty {
            return (
                normalizedChatBaseURL(requestBaseURL),
                configured?.catalogMetadata?.upstreamModelID?.trimmedNonEmpty ?? modelID
            )
        }
        if let host = autoEndpointHost(from: modelID) {
            return (
                chatBaseURL(forHost: host),
                configured?.catalogMetadata?.upstreamModelID?.trimmedNonEmpty ?? modelID
            )
        }
        return (providerBaseURL, modelID)
    }

    private static func replacingIdentity(_ model: ModelInfo, id: String) -> ModelInfo {
        ModelInfo(
            id: id,
            name: model.name,
            capabilities: model.capabilities,
            contextWindow: model.contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            reasoningConfig: model.reasoningConfig,
            overrides: model.overrides,
            catalogMetadata: model.catalogMetadata,
            isEnabled: model.isEnabled
        )
    }
}
