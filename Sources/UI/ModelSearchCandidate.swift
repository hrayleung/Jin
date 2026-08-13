import Foundation

/// Jin's field sets for fuzzy search — one place to change what is searchable.
enum ModelSearchCandidate {
    /// The provider half of a model's field set, built once per provider and shared
    /// by every one of its models.
    ///
    /// `.none` is for surfaces already scoped to a single provider (the fetched-models
    /// sheet, the provider settings list): there the provider name is a constant, so
    /// including it could only add a uniform score to every row.
    struct ProviderContext {
        static let none = ProviderContext(name: "", typeRaw: "")

        let fields: [FuzzyMatchField]

        init(name: String, typeRaw: String) {
            let cache = FuzzyMatchFieldCache.shared
            var fields = [
                cache.field(name, prominence: .primary),
                cache.field(typeRaw, prominence: .secondary)
            ]
            // The seeded display name ("OpenCode Go") is usually what the user types,
            // but `provider.name` is editable and may have been renamed away from it.
            if let displayName = ProviderType(rawValue: typeRaw)?.displayName, displayName != name {
                fields.append(cache.field(displayName, prominence: .secondary))
            }
            self.fields = fields
        }

        init(_ snapshot: ModelPickerSupport.ProviderSnapshot) {
            self.init(name: snapshot.name, typeRaw: snapshot.typeRaw)
        }
    }

    /// A model, searchable by its own name and ID *and* by the provider hosting it,
    /// so "opencode luna" can spend one token on each.
    ///
    /// `provider.baseURL` and `provider.id` are deliberately excluded: every base URL
    /// contains `https`, `api`, `com`, and `v1`, and user-created providers get
    /// UUID-shaped IDs. Both are pure noise in a model picker.
    static func model(_ model: ModelInfo, in provider: ProviderContext) -> FuzzyMatchCandidate {
        let cache = FuzzyMatchFieldCache.shared
        var fields = [
            cache.field(model.name, prominence: .primary),
            cache.field(model.id, prominence: .secondary)
        ]
        if let visibleID = ModalEndpointSupport.userFacingModelID(for: model), visibleID != model.id {
            fields.append(cache.field(visibleID, prominence: .primary))
        }
        // Aggregator IDs bury the real name behind routing segments
        // ("accounts/fireworks/models/kimi-k3"). Indexing the tail separately lets
        // "kimi-k3" land an exact match instead of a mid-string substring.
        let searchableID = ModalEndpointSupport.catalogModelID(for: model)
        if let tail = identifierTail(of: searchableID) {
            fields.append(cache.field(tail, prominence: .secondary))
        }
        fields.append(contentsOf: provider.fields)
        return FuzzyMatchCandidate(fields: fields)
    }

    static func managedAgent(_ agent: ClaudeManagedAgentDescriptor) -> FuzzyMatchCandidate {
        let cache = FuzzyMatchFieldCache.shared
        return FuzzyMatchCandidate(fields: [
            cache.field(agent.name, prominence: .primary),
            cache.field(agent.modelDisplayName ?? "", prominence: .primary),
            cache.field(agent.id, prominence: .secondary),
            cache.field(agent.modelID ?? "", prominence: .secondary)
        ])
    }

    private static func identifierTail(of identifier: String) -> String? {
        guard let separator = identifier.lastIndex(of: "/") else { return nil }
        let tail = identifier[identifier.index(after: separator)...]
        return tail.isEmpty ? nil : String(tail)
    }
}
