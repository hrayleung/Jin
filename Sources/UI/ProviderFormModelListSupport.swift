import Collections
import Foundation

extension ProviderFormSupport {
    /// Everything the provider form's model list derives from the stored models,
    /// resolved in a single pass.
    ///
    /// These were separate computed properties on `ProviderConfigFormView`, and
    /// that is what beachballed the OpenRouter pane. Computed properties re-derive
    /// on every read, and these nested: the summary's `isFullySupported` closure
    /// rebuilt the entire fully-supported set once per model, and building that set
    /// scanned the model array once per model to look up a model it was already
    /// holding. Reading `enabledModelCount` a single time was O(n^3) — 4.6s for
    /// OpenRouter's 435 models — and one body pass read the summary five times plus
    /// the set once per rendered row. Derive once, pass the value down.
    struct ModelListState {
        let models: [ModelInfo]
        let filteredModels: [ModelInfo]
        let fullySupportedModelIDs: Set<String>
        let enabledByModelID: [String: Bool]
        let summary: ModelListSummary
        let canKeepFullySupportedModels: Bool
        let canKeepEnabledModels: Bool

        /// The rows draw their own separators (they live in a `LazyVStack`, not a
        /// `List`) and the trailing one has to be suppressed. Stored, not computed —
        /// this struct exists precisely because SwiftUI re-evaluates computed
        /// properties on every read.
        let lastFilteredModelID: String?

        var isEmpty: Bool { models.isEmpty }
    }

    static func modelListState(
        models: [ModelInfo],
        searchText: String,
        providerType: ProviderType?
    ) -> ModelListState {
        let fullySupportedModelIDs = fullySupportedModelIDs(models, providerType: providerType)
        // The predicate must be O(1). Handing `modelListSummary` a closure that
        // rebuilds the set is what turned a count into an O(n^3) walk.
        let summary = modelListSummary(models: models) { fullySupportedModelIDs.contains($0) }

        let filtered = filteredModels(models, searchText: searchText)

        return ModelListState(
            models: models,
            filteredModels: filtered,
            fullySupportedModelIDs: fullySupportedModelIDs,
            enabledByModelID: enabledByModelID(models),
            summary: summary,
            canKeepFullySupportedModels: summary.canKeepFullySupportedModels(
                hasProviderType: providerType != nil
            ),
            canKeepEnabledModels: summary.canKeepEnabledModels,
            lastFilteredModelID: filtered.last?.id
        )
    }

    /// Resolves each model's catalog ID from the model already in hand. The form
    /// used to look the model back up by ID from inside this loop, which made a
    /// single set build quadratic on its own.
    static func fullySupportedModelIDs(
        _ models: [ModelInfo],
        providerType: ProviderType?
    ) -> Set<String> {
        guard let providerType else { return [] }

        var ids = Set<String>()
        for model in models where JinModelSupport.isFullySupported(
            providerType: providerType,
            modelID: ModalEndpointSupport.catalogModelID(for: model)
        ) {
            ids.insert(model.id)
        }
        return ids
    }

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

    static func enabledByModelID(_ models: [ModelInfo]) -> [String: Bool] {
        Dictionary(models.map { ($0.id, $0.isEnabled) }, uniquingKeysWith: { _, last in last })
    }

    static func fullySupportedModelIDs(
        _ models: [ModelInfo],
        isFullySupported: (String) -> Bool
    ) -> Set<String> {
        Set(models.compactMap { isFullySupported($0.id) ? $0.id : nil })
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
