import Foundation

/// Unified source of truth for all known model metadata.
///
/// Capabilities, context windows, reasoning configs, and fully-supported status
/// are all defined here — no string-matching heuristics in adapters or UI code.
///
/// Usage:
///   ModelCatalog.entry(for: "claude-sonnet-4-6", provider: .anthropic)
///   ModelCatalog.modelInfo(for: "anthropic/claude-sonnet-4-6", provider: .cloudflareAIGateway)
///   ModelCatalog.seededModels(for: .anthropic)  // ordered list for first-launch seeding
struct ModelCatalogEntry {
    let capabilities: ModelCapability
    let contextWindow: Int
    let maxOutputTokens: Int?
    let reasoningConfig: ModelReasoningConfig?
    let isFullySupported: Bool
    let displayName: String
    /// Wire/UI features declared on the catalog record (dual-read with `ModelCapabilityRegistry`).
    let features: ModelFeatures
}

enum ModelCatalog {
    private static let conservativeUnknownCapabilities: ModelCapability = [.streaming, .toolCalling]
    private static let conservativeUnknownContextWindow = 128_000

    // MARK: - Internal record

    struct Record {
        let id: String
        let displayName: String
        let capabilities: ModelCapability
        let contextWindow: Int
        let maxOutputTokens: Int?
        let reasoningConfig: ModelReasoningConfig?
        let isFullySupported: Bool
        /// Whether this model appears in the first-launch seed list.
        let isSeeded: Bool
        /// Optional wire/UI features. Unspecified fields fall back to `ModelCapabilityRegistry`.
        let features: ModelFeatures

        init(
            id: String,
            displayName: String,
            capabilities: ModelCapability,
            contextWindow: Int,
            maxOutputTokens: Int? = nil,
            reasoningConfig: ModelReasoningConfig?,
            isFullySupported: Bool,
            isSeeded: Bool,
            features: ModelFeatures = .unspecified
        ) {
            self.id = id
            self.displayName = displayName
            self.capabilities = capabilities
            self.contextWindow = contextWindow
            self.maxOutputTokens = maxOutputTokens
            self.reasoningConfig = reasoningConfig
            self.isFullySupported = isFullySupported
            self.isSeeded = isSeeded
            self.features = features
        }

        var entry: ModelCatalogEntry {
            ModelCatalogEntry(
                capabilities: capabilities,
                contextWindow: contextWindow,
                maxOutputTokens: maxOutputTokens,
                reasoningConfig: reasoningConfig,
                isFullySupported: isFullySupported,
                displayName: displayName,
                features: features
            )
        }
    }

    // MARK: - Public API

    /// Returns the catalog entry for a known (provider, modelID) pair, or nil for unknown models.
    /// Accepts bare IDs and common prefixed forms (`openai/…`, `models/…`, `anthropic/…`).
    static func entry(for modelID: String, provider: ProviderType) -> ModelCatalogEntry? {
        let key = catalogLookupKey(for: modelID, provider: provider)
        if provider == .openaiWebSocket {
            guard let record = lookup[.openai]?[key] else { return nil }
            let isFullySupported = record.isFullySupported && isOpenAIWebSocketAdapterCompatible(record)
            let mergedFeatures = features(for: modelID, provider: provider) ?? record.features
            return ModelCatalogEntry(
                capabilities: record.capabilities,
                contextWindow: record.contextWindow,
                maxOutputTokens: record.maxOutputTokens,
                reasoningConfig: record.reasoningConfig,
                isFullySupported: isFullySupported,
                displayName: record.displayName,
                features: mergedFeatures
            )
        }
        guard let record = lookup[provider]?[key] else { return nil }
        let mergedFeatures = features(for: modelID, provider: provider) ?? record.features
        return ModelCatalogEntry(
            capabilities: record.capabilities,
            contextWindow: record.contextWindow,
            maxOutputTokens: record.maxOutputTokens,
            reasoningConfig: record.reasoningConfig,
            isFullySupported: record.isFullySupported,
            displayName: record.displayName,
            features: mergedFeatures
        )
    }

    /// Returns a ModelInfo for the given model ID. Uses catalog data for known models;
    /// unknown IDs always receive conservative defaults.
    static func modelInfo(for modelID: String, provider: ProviderType, name: String? = nil) -> ModelInfo {
        if let e = entry(for: modelID, provider: provider) {
            return ModelInfo(
                id: modelID,
                name: name ?? e.displayName,
                capabilities: e.capabilities,
                contextWindow: e.contextWindow,
                maxOutputTokens: e.maxOutputTokens,
                reasoningConfig: e.reasoningConfig
            )
        }
        return fallbackModelInfo(id: modelID, name: name ?? modelID, provider: provider)
    }

    /// Returns true if the model is "fully supported" (eligible for the ✦ badge).
    static func isFullySupported(modelID: String, provider: ProviderType) -> Bool {
        entry(for: modelID, provider: provider)?.isFullySupported ?? false
    }

    /// Returns the ordered list of seed models for a provider (used on first launch).
    /// openaiWebSocket mirrors OpenAI's list, excluding known models the adapter cannot route.
    static func seededModels(for provider: ProviderType) -> [ModelInfo] {
        let source: ProviderType = (provider == .openaiWebSocket) ? .openai : provider
        return (orderedRecords[source] ?? [])
            .filter { record in
                record.isSeeded && (provider != .openaiWebSocket || isOpenAIWebSocketAdapterCompatible(record))
            }
            .map { r in
                ModelInfo(
                    id: r.id,
                    name: r.displayName,
                    capabilities: r.capabilities,
                    contextWindow: r.contextWindow,
                    maxOutputTokens: r.maxOutputTokens,
                    reasoningConfig: r.reasoningConfig
                )
            }
    }

    /// Returns false only for exact OpenAI catalog records that are known not to work through
    /// the OpenAI WebSocket provider's adapter routes.
    static func isOpenAIWebSocketAdapterCompatible(modelID: String) -> Bool {
        let lower = modelID.lowercased()
        guard let record = lookup[.openai]?[lower] else { return true }
        return isOpenAIWebSocketAdapterCompatible(record)
    }

    // MARK: - Cloudflare compound IDs
    // Cloudflare models are exact, fully-qualified IDs (for example `openai/gpt-5.2`).
    // Do not infer by prefix/substring from non-Cloudflare providers.

    // MARK: - Fallback for unknown models

    /// Used when the model ID is not in the catalog.
    /// Keep this conservative: exact-ID catalog entries are the only source of rich capabilities.
    private static func fallbackModelInfo(id: String, name: String, provider: ProviderType) -> ModelInfo {
        _ = provider
        return ModelInfo(
            id: id,
            name: name,
            capabilities: conservativeUnknownCapabilities,
            contextWindow: conservativeUnknownContextWindow,
            maxOutputTokens: nil,
            reasoningConfig: nil
        )
    }

    private static func isOpenAIWebSocketAdapterCompatible(_ record: Record) -> Bool {
        record.capabilities.contains(.streaming) || record.capabilities.contains(.imageGeneration)
    }
}

// Index and model record tables are in ModelCatalogRecords.swift
