import SwiftUI

extension ProviderConfigFormView {

    func providerFormPresentations<Content: View>(_ content: Content) -> some View {
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
                Text("This will delete \(nonFullySupportedModelsCount) models not marked as fully supported and keep \(fullySupportedModelsCount) fully supported model(s).")
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
                Text("This will delete \(disabledModelCount) disabled model(s) and keep \(enabledModelCount) enabled model(s).")
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
                    Text("This will delete the model \u{201C}\(modelPendingDeletion.name)\u{201D} (\(modelPendingDeletion.id)).")
                } else {
                    Text("This will remove this model from the local model list.")
                }
            }
    }
}
