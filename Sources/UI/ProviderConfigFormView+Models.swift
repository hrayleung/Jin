import SwiftUI

// MARK: - Model Management

extension ProviderConfigFormView {

    struct FetchedModelsSelectionState: Identifiable {
        let id = UUID()
        let models: [ModelInfo]
    }

    var decodedModels: [ModelInfo] {
        provider.allModels
    }

    /// Derive this once per body pass and pass the value down. Reading it from
    /// several places in one pass is what used to hang the form — see
    /// `ProviderFormSupport.ModelListState`.
    var modelListState: ProviderFormSupport.ModelListState {
        ProviderFormSupport.modelListState(
            models: decodedModels,
            searchText: modelSearchText,
            providerType: providerType
        )
    }

    func setModels(_ models: [ModelInfo]) {
        do {
            provider.modelsData = try JSONEncoder().encode(models)
            try modelContext.save()
        } catch {
            modelsError = error.localizedDescription
        }
    }

    func updateModel(_ updated: ModelInfo) {
        guard let models = ProviderFormSupport.modelUpdating(decodedModels, with: updated) else { return }
        setModels(models)
    }

    func modelEnabledBinding(modelID: String, enabledByModelID: [String: Bool]) -> Binding<Bool> {
        Binding(
            get: {
                enabledByModelID[modelID] ?? true
            },
            set: { isEnabled in
                var models = decodedModels
                guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
                models[index].isEnabled = isEnabled
                setModels(models)
            }
        )
    }

    func setAllModelsEnabled(_ enabled: Bool) {
        guard let models = ProviderFormSupport.modelsSettingEnabled(decodedModels, enabled: enabled) else { return }
        setModels(models)
    }

    func keepOnlyFullySupportedModels() {
        let models = decodedModels
        // Resolve the set once up front; the predicate itself must stay O(1).
        let fullySupportedModelIDs = ProviderFormSupport.fullySupportedModelIDs(
            models,
            providerType: providerType
        )
        guard let kept = ProviderFormSupport.modelsKeepingOnlyFullySupported(
            models,
            hasProviderType: providerType != nil,
            isFullySupported: { fullySupportedModelIDs.contains($0) }
        ) else { return }
        setModels(kept)
    }

    func keepOnlyEnabledModels() {
        guard let models = ProviderFormSupport.modelsKeepingOnlyEnabled(decodedModels) else { return }
        setModels(models)
    }

    func requestDeleteModel(_ model: ModelInfo) {
        modelPendingDeletion = model
        showingDeleteModelConfirmation = true
    }

    func deleteModel(_ model: ModelInfo) {
        guard let models = ProviderFormSupport.modelsDeleting(decodedModels, modelID: model.id) else {
            modelPendingDeletion = nil
            return
        }
        setModels(models)
        modelPendingDeletion = nil
    }

    var isFetchModelsDisabled: Bool {
        ProviderFormSupport.isFetchModelsDisabled(
            isFetchingModels: isFetchingModels,
            providerType: providerType,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON
        )
    }

    func fetchModels() async {
        guard !isFetchingModels else { return }

        await MainActor.run {
            isFetchingModels = true
            modelsError = nil
        }

        defer {
            Task { @MainActor in isFetchingModels = false }
        }

        do {
            try await saveCredentials()
            guard let config = try? provider.toDomain() else {
                throw PersistenceError.invalidProviderType(provider.typeRaw)
            }
            let adapter = try await providerManager.createAdapter(for: config)
            let fetched = try await adapter.fetchAvailableModels()
            let sorted = ProviderFormSupport.normalizedFetchedModels(fetched)
            await MainActor.run {
                if sorted.isEmpty {
                    fetchedModelsForSelection = nil
                    modelsError = "No models were returned by this provider."
                } else {
                    fetchedModelsForSelection = FetchedModelsSelectionState(models: sorted)
                }
            }
        } catch {
            await MainActor.run { modelsError = error.localizedDescription }
        }
    }

    /// Adds user-selected new models AND silently refreshes metadata for all
    /// existing models that appeared in the fetch, regardless of selection.
    /// User overrides and enabled state are always preserved.
    func addSelectedAndRefreshExisting(selected: [ModelInfo], allFetched: [ModelInfo]) -> [ModelInfo] {
        ProviderFormSupport.modelsAddingSelectedAndRefreshingExisting(
            existingModels: decodedModels,
            selectedModels: selected,
            allFetchedModels: allFetched,
            providerType: providerType
        )
    }
}
