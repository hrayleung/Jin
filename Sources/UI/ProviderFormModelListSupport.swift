import Collections
import Foundation

extension ProviderFormSupport {
    static func filteredModels(_ models: [ModelInfo], searchText: String) -> [ModelInfo] {
        guard let query = searchText.trimmedNonEmpty?.lowercased() else { return models }

        return models.filter { model in
            model.name.lowercased().contains(query) || model.id.lowercased().contains(query)
        }
    }

    static func modelListSummary(
        models: [ModelInfo],
        isFullySupported: (String) -> Bool
    ) -> ModelListSummary {
        ModelListSummary(
            totalCount: models.count,
            enabledCount: models.filter(\.isEnabled).count,
            fullySupportedCount: models.filter { isFullySupported($0.id) }.count
        )
    }

    static func modelUpdating(_ models: [ModelInfo], with updated: ModelInfo) -> [ModelInfo]? {
        var models = models
        guard let index = models.firstIndex(where: { $0.id == updated.id }) else { return nil }
        models[index] = updated
        return models
    }

    static func modelsSettingEnabled(_ models: [ModelInfo], enabled: Bool) -> [ModelInfo]? {
        guard !models.isEmpty else { return nil }
        return models.map { model in
            modelCopy(from: model, overrides: model.overrides, isEnabled: enabled)
        }
    }

    static func modelsKeepingOnlyFullySupported(
        _ models: [ModelInfo],
        hasProviderType: Bool,
        isFullySupported: (String) -> Bool
    ) -> [ModelInfo]? {
        guard hasProviderType else { return nil }
        let filtered = models.filter { isFullySupported($0.id) }
        guard !filtered.isEmpty else { return nil }
        return filtered
    }

    static func modelsKeepingOnlyEnabled(_ models: [ModelInfo]) -> [ModelInfo]? {
        let filtered = models.filter(\.isEnabled)
        guard !filtered.isEmpty, filtered.count < models.count else { return nil }
        return filtered
    }

    static func modelsDeleting(_ models: [ModelInfo], modelID: String) -> [ModelInfo]? {
        var models = models
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return nil }
        models.remove(at: index)
        return models
    }

    static func modelsUpsertingAndSorting(_ models: [ModelInfo], model: ModelInfo) -> [ModelInfo] {
        var models = models
        if let existingIndex = models.firstIndex(where: { $0.id == model.id }) {
            models[existingIndex] = model
        } else {
            models.append(model)
        }
        return sortedModelsByName(models)
    }

    static func normalizedFetchedModels(_ fetched: [ModelInfo]) -> [ModelInfo] {
        var seenIDs = OrderedSet<String>()
        let deduplicated = fetched.filter { model in
            guard !seenIDs.contains(model.id) else { return false }
            seenIDs.append(model.id)
            return true
        }

        return sortedModelsByName(deduplicated)
    }

    static func modelsAddingSelectedAndRefreshingExisting(
        existingModels: [ModelInfo],
        selectedModels: [ModelInfo],
        allFetchedModels: [ModelInfo],
        providerType: ProviderType?
    ) -> [ModelInfo] {
        let existingByID = existingModels.reduce(into: [String: ModelInfo]()) { $0[$1.id] = $1 }
        let fetchedByID = allFetchedModels.reduce(into: [String: ModelInfo]()) { $0[$1.id] = $1 }
        var resultByID = refreshedExistingModels(
            existingByID: existingByID,
            fetchedByID: fetchedByID
        )

        if providerType == .githubCopilot {
            migrateGitHubCopilotLegacyModels(
                resultByID: &resultByID,
                existingByID: existingByID,
                fetchedByID: fetchedByID,
                allFetchedModels: allFetchedModels
            )
        }

        addNewSelections(
            selectedModels,
            existingByID: existingByID,
            resultByID: &resultByID
        )

        return sortedModelsByName(Array(resultByID.values))
    }

    private static func refreshedExistingModels(
        existingByID: [String: ModelInfo],
        fetchedByID: [String: ModelInfo]
    ) -> [String: ModelInfo] {
        var resultByID = existingByID
        for (id, existing) in existingByID {
            guard let fetched = fetchedByID[id] else { continue }
            resultByID[id] = mergedFetchedModel(fetched, preserving: existing)
        }
        return resultByID
    }

    private static func migrateGitHubCopilotLegacyModels(
        resultByID: inout [String: ModelInfo],
        existingByID: [String: ModelInfo],
        fetchedByID: [String: ModelInfo],
        allFetchedModels: [ModelInfo]
    ) {
        for (legacyID, existing) in existingByID where fetchedByID[legacyID] == nil {
            guard let migrated = ProviderModelAliasResolver.resolvedModel(
                for: legacyID,
                providerType: .githubCopilot,
                availableModels: allFetchedModels
            ), migrated.id != legacyID else {
                continue
            }
            resultByID.removeValue(forKey: legacyID)
            resultByID[migrated.id] = mergedFetchedModel(migrated, preserving: existing)
        }
    }

    private static func addNewSelections(
        _ selectedModels: [ModelInfo],
        existingByID: [String: ModelInfo],
        resultByID: inout [String: ModelInfo]
    ) {
        for model in selectedModels where existingByID[model.id] == nil {
            resultByID[model.id] = modelForNewSelection(model)
        }
    }

    private static func mergedFetchedModel(_ fetched: ModelInfo, preserving existing: ModelInfo) -> ModelInfo {
        modelCopy(
            from: fetched,
            overrides: existing.overrides,
            isEnabled: existing.isEnabled
        )
    }

    private static func modelForNewSelection(_ selected: ModelInfo) -> ModelInfo {
        modelCopy(from: selected, overrides: nil, isEnabled: true)
    }

    private static func modelCopy(
        from model: ModelInfo,
        overrides: ModelOverrides?,
        isEnabled: Bool
    ) -> ModelInfo {
        ModelInfo(
            id: model.id,
            name: model.name,
            capabilities: model.capabilities,
            contextWindow: model.contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            reasoningConfig: model.reasoningConfig,
            overrides: overrides,
            catalogMetadata: model.catalogMetadata,
            isEnabled: isEnabled
        )
    }

    private static func sortedModelsByName(_ models: [ModelInfo]) -> [ModelInfo] {
        models.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
