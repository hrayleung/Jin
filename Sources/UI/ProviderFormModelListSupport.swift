import Collections
import Foundation

extension ProviderFormSupport {
    /// Filters, never reorders: this is a management surface, and having rows
    /// resort under the cursor while you type makes it easy to edit the wrong model.
    /// `.structural` for the same reason — the speculative subsequence tier belongs
    /// in a chooser, not in an editor.
    static func filteredModels(_ models: [ModelInfo], searchText: String) -> [ModelInfo] {
        let query = FuzzyMatchQuery(searchText)
        guard !query.isEmpty else { return models }

        return FuzzyMatch.filter(models, query: query) { model in
            ModelSearchCandidate.model(model, in: .none)
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
        let incoming = ModalEndpointSupport.promotedIdentity(for: model)
        if let existingIndex = models.firstIndex(where: {
            $0.id == incoming.id || ModalEndpointSupport.isSameDeployment($0, incoming)
        }) {
            let existing = models[existingIndex]
            models[existingIndex] = modelCopy(
                from: incoming,
                overrides: existing.overrides,
                isEnabled: existing.isEnabled
            )
        } else {
            models.append(incoming)
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
        for model in selectedModels {
            let incoming = ModalEndpointSupport.promotedIdentity(for: model)
            if existingByID[incoming.id] != nil { continue }
            if resultByID.values.contains(where: { ModalEndpointSupport.isSameDeployment($0, incoming) }) {
                continue
            }
            resultByID[incoming.id] = modelForNewSelection(incoming)
        }
    }

    private static func mergedFetchedModel(_ fetched: ModelInfo, preserving existing: ModelInfo) -> ModelInfo {
        var metadata = fetched.catalogMetadata ?? ModelCatalogMetadata()
        if metadata.requestBaseURL?.trimmedNonEmpty == nil {
            metadata.requestBaseURL = existing.catalogMetadata?.requestBaseURL
        }
        if metadata.upstreamModelID?.trimmedNonEmpty == nil {
            metadata.upstreamModelID = existing.catalogMetadata?.upstreamModelID
        }
        if metadata.availabilityMessage?.trimmedNonEmpty == nil {
            metadata.availabilityMessage = existing.catalogMetadata?.availabilityMessage
        }
        var merged = fetched
        merged.catalogMetadata = metadata.isEmpty ? nil : metadata
        return modelCopy(
            from: merged,
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
