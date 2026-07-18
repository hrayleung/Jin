import Foundation

// MARK: - Feature resolution (catalog-layer)

extension ModelCatalog {
    /// Resolved features for a (provider, modelID) pair.
    ///
    /// Merge order (later wins for non-nil fields when using `filling`):
    /// 1. Provider declared feature table (exact ID)
    /// 2. `Record.features` on the catalog entry (inline overrides)
    ///
    /// Returns `nil` only when neither a record nor a declared table row exists.
    static func features(for modelID: String, provider: ProviderType) -> ModelFeatures? {
        let lookupKey = catalogLookupKey(for: modelID, provider: provider)
        let table = declaredFeaturesTable(for: provider)?[lookupKey]
        let recordFeatures = lookup[provider]?[lookupKey]?.features
            ?? (provider == .openaiWebSocket ? lookup[.openai]?[lookupKey]?.features : nil)

        switch (table, recordFeatures) {
        case let (table?, record?):
            return record.filling(from: table)
        case let (table?, nil):
            return table
        case let (nil, record?):
            return record
        case (nil, nil):
            return nil
        }
    }

    /// Provider-aware bare model ID for catalog records and feature tables.
    /// Strips gateway / resource prefixes (`openai/`, `models/`, `anthropic/`, …).
    static func catalogLookupKey(for modelID: String, provider: ProviderType) -> String {
        let lower = modelID.lowercased()
        switch provider {
        case .gemini, .vertexai:
            return canonicalGoogleModelID(lower)
        case .openai, .openaiWebSocket:
            if lower.hasPrefix("openai/") {
                return String(lower.dropFirst("openai/".count))
            }
            return lower
        case .anthropic, .claudeManagedAgents:
            if lower.hasPrefix("anthropic/") {
                return String(lower.dropFirst("anthropic/".count))
            }
            return lower
        default:
            return lower
        }
    }

    private static func featureLookupKey(for modelID: String, provider: ProviderType) -> String {
        catalogLookupKey(for: modelID, provider: provider)
    }

    private static func declaredFeaturesTable(for provider: ProviderType) -> [String: ModelFeatures]? {
        switch provider {
        case .openai, .openaiWebSocket:
            return openAIDeclaredFeaturesByID
        case .anthropic:
            // Claude Managed Agents intentionally disable native web search / code exec
            // at the registry layer; only pure Anthropic uses this table.
            return anthropicDeclaredFeaturesByID
        case .claudeManagedAgents:
            return nil
        case .gemini:
            return geminiDeclaredFeaturesByID
        case .vertexai:
            return vertexDeclaredFeaturesByID
        default:
            return nil
        }
    }
}
