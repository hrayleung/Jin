import SwiftUI

// MARK: - Model Management

extension ProviderConfigFormView {

    struct FetchedModelsSelectionState: Identifiable {
        let id = UUID()
        let models: [ModelInfo]
    }

    func isFullySupportedModel(_ modelID: String) -> Bool {
        guard let providerType else { return false }
        return JinModelSupport.isFullySupported(providerType: providerType, modelID: modelID)
    }

    var decodedModels: [ModelInfo] {
        provider.allModels
    }

    var filteredModels: [ModelInfo] {
        ProviderFormSupport.filteredModels(decodedModels, searchText: modelSearchText)
    }

    var modelListSummary: ProviderFormSupport.ModelListSummary {
        ProviderFormSupport.modelListSummary(
            models: decodedModels,
            isFullySupported: isFullySupportedModel
        )
    }

    var enabledModelCount: Int {
        modelListSummary.enabledCount
    }

    var fullySupportedModelsCount: Int {
        modelListSummary.fullySupportedCount
    }

    var nonFullySupportedModelsCount: Int {
        modelListSummary.nonFullySupportedCount
    }

    var disabledModelCount: Int {
        modelListSummary.disabledCount
    }

    var canKeepFullySupportedModels: Bool {
        modelListSummary.canKeepFullySupportedModels(hasProviderType: providerType != nil)
    }

    var canKeepEnabledModels: Bool {
        modelListSummary.canKeepEnabledModels
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

    func modelEnabledBinding(modelID: String) -> Binding<Bool> {
        Binding(
            get: {
                decodedModels.first(where: { $0.id == modelID })?.isEnabled ?? true
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
        guard let models = ProviderFormSupport.modelsKeepingOnlyFullySupported(
            decodedModels,
            hasProviderType: providerType != nil,
            isFullySupported: isFullySupportedModel
        ) else { return }
        setModels(models)
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
            codexCanUseCurrentAuthenticationMode: codexCanUseCurrentAuthenticationMode,
            codexAuthIsWorking: codexAuthStatus == .working,
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
