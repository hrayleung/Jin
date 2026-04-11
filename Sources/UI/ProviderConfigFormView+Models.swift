import Collections
import SwiftUI

// MARK: - Model Management

extension ProviderConfigFormView {

    func isFullySupportedModel(_ modelID: String) -> Bool {
        guard let providerType else { return false }
        return JinModelSupport.isFullySupported(providerType: providerType, modelID: modelID)
    }

    var decodedModels: [ModelInfo] {
        provider.allModels
    }

    var filteredModels: [ModelInfo] {
        let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return decodedModels }

        return decodedModels.filter { model in
            model.name.lowercased().contains(query) || model.id.lowercased().contains(query)
        }
    }

    var enabledModelCount: Int {
        decodedModels.filter(\.isEnabled).count
    }

    var fullySupportedModelsCount: Int {
        decodedModels.filter { isFullySupportedModel($0.id) }.count
    }

    var nonFullySupportedModelsCount: Int {
        decodedModels.count - fullySupportedModelsCount
    }

    var disabledModelCount: Int {
        decodedModels.count - enabledModelCount
    }

    var canKeepFullySupportedModels: Bool {
        guard providerType != nil else { return false }
        return fullySupportedModelsCount > 0 && nonFullySupportedModelsCount > 0
    }

    var canKeepEnabledModels: Bool {
        enabledModelCount > 0 && disabledModelCount > 0
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
        var models = decodedModels
        guard let index = models.firstIndex(where: { $0.id == updated.id }) else { return }
        models[index] = updated
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
        guard !decodedModels.isEmpty else { return }
        let models = decodedModels.map { model in
            ModelInfo(
                id: model.id,
                name: model.name,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                maxOutputTokens: model.maxOutputTokens,
                reasoningConfig: model.reasoningConfig,
                overrides: model.overrides,
                catalogMetadata: model.catalogMetadata,
                isEnabled: enabled
            )
        }
        setModels(models)
    }

    func keepOnlyFullySupportedModels() {
        guard providerType != nil else { return }
        let filteredModels = decodedModels.filter { isFullySupportedModel($0.id) }
        guard !filteredModels.isEmpty else { return }
        setModels(filteredModels)
    }

    func keepOnlyEnabledModels() {
        let filteredModels = decodedModels.filter(\.isEnabled)
        guard !filteredModels.isEmpty, filteredModels.count < decodedModels.count else { return }
        setModels(filteredModels)
    }

    func requestDeleteModel(_ model: ModelInfo) {
        modelPendingDeletion = model
        showingDeleteModelConfirmation = true
    }

    func deleteModel(_ model: ModelInfo) {
        var updatedModels = decodedModels
        guard let index = updatedModels.firstIndex(where: { $0.id == model.id }) else {
            modelPendingDeletion = nil
            return
        }
        updatedModels.remove(at: index)
        setModels(updatedModels)
        modelPendingDeletion = nil
    }

    var isFetchModelsDisabled: Bool {
        guard !isFetchingModels else { return true }
        switch providerType {
        case .codexAppServer:
            return !codexCanUseCurrentAuthenticationMode || codexAuthStatus == .working
        case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .gemini:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vertexai:
            return serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .none:
            return true
        }
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
            var seenIDs = OrderedSet<String>()
            let deduplicated = fetched.filter { model in
                guard !seenIDs.contains(model.id) else { return false }
                seenIDs.append(model.id)
                return true
            }
            let sorted = deduplicated.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
        let existingByID = decodedModels.reduce(into: [String: ModelInfo]()) { $0[$1.id] = $1 }
        let fetchedByID = allFetched.reduce(into: [String: ModelInfo]()) { $0[$1.id] = $1 }
        var resultByID = existingByID

        func mergedModel(from fetched: ModelInfo, preserving existing: ModelInfo) -> ModelInfo {
            ModelInfo(
                id: fetched.id,
                name: fetched.name,
                capabilities: fetched.capabilities,
                contextWindow: fetched.contextWindow,
                maxOutputTokens: fetched.maxOutputTokens,
                reasoningConfig: fetched.reasoningConfig,
                overrides: existing.overrides,
                catalogMetadata: fetched.catalogMetadata,
                isEnabled: existing.isEnabled
            )
        }

        // Refresh metadata for existing models that appeared in the fetch
        for (id, fetched) in fetchedByID where existingByID[id] != nil {
            let existing = existingByID[id]!
            resultByID[id] = mergedModel(from: fetched, preserving: existing)
        }

        if providerType == .githubCopilot {
            for (legacyID, existing) in existingByID where fetchedByID[legacyID] == nil {
                guard let migrated = ProviderModelAliasResolver.resolvedModel(
                    for: legacyID,
                    providerType: .githubCopilot,
                    availableModels: allFetched
                ), migrated.id != legacyID else {
                    continue
                }
                resultByID.removeValue(forKey: legacyID)
                resultByID[migrated.id] = mergedModel(from: migrated, preserving: existing)
            }
        }

        // Add newly selected models that don't already exist
        for model in selected where existingByID[model.id] == nil {
            resultByID[model.id] = ModelInfo(
                id: model.id,
                name: model.name,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                maxOutputTokens: model.maxOutputTokens,
                reasoningConfig: model.reasoningConfig,
                overrides: nil,
                catalogMetadata: model.catalogMetadata,
                isEnabled: true
            )
        }

        return resultByID.values.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
