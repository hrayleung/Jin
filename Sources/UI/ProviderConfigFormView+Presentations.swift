import SwiftUI

extension ProviderConfigFormView {

    /// `modelList` is threaded in rather than read from the view: the dialog
    /// `message:` builders are non-escaping, so their counts are resolved on every
    /// body pass, presented or not.
    func providerFormPresentations<Content: View>(
        _ content: Content,
        modelList: ProviderFormSupport.ModelListState
    ) -> some View {
        content
            .sheet(item: $fetchedModelsForSelection) { selection in
                FetchedModelsSelectionSheet(
                    fetchedModels: selection.models,
                    existingModelIDs: Set(decodedModels.map(\.id)),
                    providerType: providerType,
                    onConfirm: { selectedModels in
                        let merged = addSelectedAndRefreshExisting(
                            selected: selectedModels,
                            allFetched: selection.models
                        )
                        setModels(merged)
                    }
                )
            }
            .sheet(isPresented: $showingAddModel) {
                AddModelSheet(
                    providerType: providerType,
                    onAdd: { model in
                        setModels(ProviderFormSupport.modelsUpsertingAndSorting(decodedModels, model: model))
                    }
                )
            }
            .sheet(isPresented: $showingAddEndpoint) {
                AddModalEndpointSheet(
                    apiKey: apiKey,
                    onAdd: { model in
                        setModels(ProviderFormSupport.modelsUpsertingAndSorting(decodedModels, model: model))
                    }
                )
            }
            .sheet(item: $editingModel) { model in
                ModelSettingsSheet(
                    model: model,
                    providerType: providerType,
                    onSave: { updated in
                        updateModel(updated)
                    }
                )
            }
            .confirmationDialog(
                "Delete all models for \(provider.name)?",
                isPresented: $showingDeleteAllModelsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    setModels([])
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the local model list. You can fetch it again anytime.")
            }
            .confirmationDialog(
                "Keep fully supported models for \(provider.name)?",
                isPresented: $showingKeepFullySupportedModelsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Keep Fully Supported", role: .destructive) {
                    keepOnlyFullySupportedModels()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete \(modelList.summary.nonFullySupportedCount) models not marked as fully supported and keep \(modelList.summary.fullySupportedCount) fully supported model(s).")
            }
            .confirmationDialog(
                "Keep enabled models for \(provider.name)?",
                isPresented: $showingKeepEnabledModelsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Keep Enabled", role: .destructive) {
                    keepOnlyEnabledModels()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete \(modelList.summary.disabledCount) disabled model(s) and keep \(modelList.summary.enabledCount) enabled model(s).")
            }
            .confirmationDialog(
                "Delete model for \(provider.name)?",
                isPresented: $showingDeleteModelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let modelPendingDeletion {
                        deleteModel(modelPendingDeletion)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let modelPendingDeletion {
                    Text(deleteConfirmationMessage(for: modelPendingDeletion))
                } else {
                    Text("This will remove this model from the local model list.")
                }
            }
    }

    private func deleteConfirmationMessage(for model: ModelInfo) -> String {
        if let visibleID = ModalEndpointSupport.userFacingModelID(for: model), visibleID != model.name {
            return "This will delete the model \u{201C}\(model.name)\u{201D} (\(visibleID))."
        }
        return "This will delete the model \u{201C}\(model.name)\u{201D}."
    }
}
