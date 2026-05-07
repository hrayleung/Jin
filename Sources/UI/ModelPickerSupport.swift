import Foundation

enum ModelPickerScope: String, CaseIterable, Identifiable {
    case all = "All"
    case favorites = "Favorites"

    var id: String { rawValue }
}

enum ModelPickerSupport {
    struct ProviderSnapshot {
        let id: String
        let name: String
        let typeRaw: String
        let isEnabled: Bool
        let selectableModels: [ModelInfo]
    }

    struct ProviderSection: Identifiable {
        let providerID: String
        let models: [ModelInfo]

        var id: String { providerID }
    }

    struct ScopedModel: Identifiable {
        let providerID: String
        let model: ModelInfo
        let index: Int

        var id: String { "\(providerID)::\(model.id)::\(index)" }
    }

    static let searchPlaceholder = "Search"

    static func trimmedSearchText(_ searchText: String) -> String {
        searchText.trimmed
    }

    static func shouldShowManagedAgentSection(
        hasManagedAgentContext: Bool,
        trimmedSearchText: String,
        filteredManagedAgents: [ClaudeManagedAgentDescriptor]
    ) -> Bool {
        guard hasManagedAgentContext else { return false }
        return trimmedSearchText.isEmpty || !filteredManagedAgents.isEmpty
    }

    static func filteredManagedAgents(
        _ agents: [ClaudeManagedAgentDescriptor],
        searchText: String
    ) -> [ClaudeManagedAgentDescriptor] {
        let query = trimmedSearchText(searchText)
        guard !query.isEmpty else { return agents }

        return fuzzySortedMatches(agents, query: query) { agent in
            [agent.name, agent.id, agent.modelDisplayName ?? "", agent.modelID ?? ""]
        }
    }

    static func selectedManagedAgentName(
        selectedAgentID: String?,
        availableAgents: [ClaudeManagedAgentDescriptor]
    ) -> String? {
        guard let selectedAgentID else { return nil }
        return availableAgents.first(where: { $0.id == selectedAgentID })?.name ?? selectedAgentID
    }

    static func emptyStateTitle(scope: ModelPickerScope) -> String {
        scope == .favorites ? "No favorite models" : "No results"
    }

    static func emptyStateDescription(scope: ModelPickerScope) -> String {
        scope == .favorites ? "Star a model to pin it here." : "Try another search."
    }

    static func managedAgentEmptyRowText(trimmedSearchText: String) -> String {
        trimmedSearchText.isEmpty ? "No agents" : "No matches"
    }

    static func filteredSections(
        providers: [ProviderSnapshot],
        scope: ModelPickerScope,
        searchText: String,
        managedAgentProviderID: String?,
        isFavorite: (String, String) -> Bool
    ) -> [ProviderSection] {
        let query = trimmedSearchText(searchText)
        return selectableProviders(
            from: providers,
            managedAgentProviderID: managedAgentProviderID
        ).compactMap { provider in
            section(
                for: provider,
                scope: scope,
                query: query,
                isFavorite: isFavorite
            )
        }
    }

    static func scopedModels(providerID: String, models: [ModelInfo]) -> [ScopedModel] {
        models.enumerated().map { index, model in
            ScopedModel(providerID: providerID, model: model, index: index)
        }
    }

    private static func fuzzySortedMatches<Value>(
        _ values: [Value],
        query: String,
        candidates: (Value) -> [String]
    ) -> [Value] {
        values
            .compactMap { value -> (value: Value, score: Int)? in
                let result = FuzzyMatch.bestMatch(query: query, candidates: candidates(value))
                guard result.matched else { return nil }
                return (value, result.score)
            }
            .sorted { $0.score > $1.score }
            .map(\.value)
    }

    private static func selectableProviders(
        from providers: [ProviderSnapshot],
        managedAgentProviderID: String?
    ) -> [ProviderSnapshot] {
        providers
            .filter { provider in
                provider.isEnabled && provider.id != managedAgentProviderID
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func section(
        for provider: ProviderSnapshot,
        scope: ModelPickerScope,
        query: String,
        isFavorite: (String, String) -> Bool
    ) -> ProviderSection? {
        let models = filteredModels(
            for: provider,
            scope: scope,
            query: query,
            isFavorite: isFavorite
        )
        guard !models.isEmpty else { return nil }
        return ProviderSection(providerID: provider.id, models: models)
    }

    private static func filteredModels(
        for provider: ProviderSnapshot,
        scope: ModelPickerScope,
        query: String,
        isFavorite: (String, String) -> Bool
    ) -> [ModelInfo] {
        let models = scopedSelectableModels(
            for: provider,
            scope: scope,
            isFavorite: isFavorite
        )

        guard !models.isEmpty, !query.isEmpty else { return models }
        guard !providerMatches(provider, query: query) else { return models }

        return fuzzySortedMatches(models, query: query) { model in
            [model.name, model.id]
        }
    }

    private static func scopedSelectableModels(
        for provider: ProviderSnapshot,
        scope: ModelPickerScope,
        isFavorite: (String, String) -> Bool
    ) -> [ModelInfo] {
        guard scope == .favorites else { return provider.selectableModels }
        return provider.selectableModels.filter { isFavorite(provider.id, $0.id) }
    }

    private static func providerMatches(_ provider: ProviderSnapshot, query: String) -> Bool {
        FuzzyMatch.bestMatch(
            query: query,
            candidates: [provider.name, provider.typeRaw]
        ).matched
    }
}
