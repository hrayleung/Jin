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
    let reasoningConfig: ModelReasoningConfig?
    let isFullySupported: Bool
    let displayName: String
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
        let reasoningConfig: ModelReasoningConfig?
        let isFullySupported: Bool
        /// Whether this model appears in the first-launch seed list.
        let isSeeded: Bool

        var entry: ModelCatalogEntry {
            ModelCatalogEntry(
                capabilities: capabilities,
                contextWindow: contextWindow,
                reasoningConfig: reasoningConfig,
                isFullySupported: isFullySupported,
                displayName: displayName
            )
        }
    }

    // MARK: - Public API

    /// Returns the catalog entry for a known (provider, modelID) pair, or nil for unknown models.
    static func entry(for modelID: String, provider: ProviderType) -> ModelCatalogEntry? {
        let lower = modelID.lowercased()
        // openaiWebSocket shares the openai model set.
        let lookupProvider: ProviderType = (provider == .openaiWebSocket) ? .openai : provider
        return lookup[lookupProvider]?[lower]?.entry
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
    /// openaiWebSocket mirrors openai's list.
    static func seededModels(for provider: ProviderType) -> [ModelInfo] {
        let source: ProviderType = (provider == .openaiWebSocket) ? .openai : provider
        return (orderedRecords[source] ?? [])
            .filter { $0.isSeeded }
            .map { r in
                ModelInfo(
                    id: r.id,
                    name: r.displayName,
                    capabilities: r.capabilities,
                    contextWindow: r.contextWindow,
                    reasoningConfig: r.reasoningConfig
                )
            }
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
            reasoningConfig: nil
        )
    }
}

// Index and model record tables are in ModelCatalogRecords.swift
