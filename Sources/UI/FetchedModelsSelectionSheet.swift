import SwiftUI

struct FetchedModelsSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let fetchedModels: [ModelInfo]
    let existingModelIDs: Set<String>
    let onConfirm: ([ModelInfo]) -> Void

    private let fullySupportedModelIDs: Set<String>

    @State private var selectedIDs: Set<String>
    @State private var searchText: String
    @State private var filterMode: FetchedModelsSelectionFilterMode

    init(
        fetchedModels: [ModelInfo],
        existingModelIDs: Set<String>,
        providerType: ProviderType?,
        onConfirm: @escaping ([ModelInfo]) -> Void
    ) {
        self.fetchedModels = fetchedModels
        self.existingModelIDs = existingModelIDs
        self.onConfirm = onConfirm
        self.fullySupportedModelIDs = ProviderFormSupport.fullySupportedModelIDs(
            fetchedModels,
            providerType: providerType
        )

        let newModelIDs = FetchedModelsSelectionSupport.initialSelectedIDs(
            fetchedModels: fetchedModels,
            existingModelIDs: existingModelIDs
        )
        _selectedIDs = State(initialValue: newModelIDs)
        _searchText = State(initialValue: "")
        _filterMode = State(initialValue: FetchedModelsSelectionSupport.initialFilterMode(selectedIDs: newModelIDs))
    }

    var body: some View {
        let models = visibleModels
        VStack(spacing: 0) {
            FetchedModelsSelectionHeaderBar(
                selectionLabel: selectionLabel,
                searchText: $searchText,
                filterMode: $filterMode
            )
            Divider()
            FetchedModelsSelectionModelListContent(
                fetchedModelsEmpty: fetchedModels.isEmpty,
                models: models,
                existingModelIDs: existingModelIDs,
                selectedIDs: selectedIDs,
                isFullySupported: isFullySupported,
                onToggleModel: toggleModel
            )
            Divider()
            FetchedModelsSelectionBottomBar(
                confirmButtonLabel: confirmButtonLabel,
                isConfirmDisabled: isConfirmDisabled,
                isSelectAllDisabled: FetchedModelsSelectionSupport.isSelectAllDisabled(
                    models: models,
                    selectedIDs: selectedIDs
                ),
                isDeselectAllDisabled: selectedIDs.isEmpty,
                onConfirm: confirmSelection,
                onCancel: { dismiss() },
                onSelectAll: { selectAll(models) },
                onDeselectAll: deselectAll
            )
        }
        .background(JinSemanticColor.detailSurface)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 480, idealHeight: 560)
    }

    // MARK: - Labels

    private var selectionLabel: String {
        FetchedModelsSelectionSupport.selectionLabel(selectedCount: selectedIDs.count)
    }

    private var confirmButtonLabel: String {
        FetchedModelsSelectionSupport.confirmButtonLabel(selectedCount: selectedIDs.count)
    }

    // MARK: - Computed

    private var visibleModels: [ModelInfo] {
        FetchedModelsSelectionSupport.visibleModels(
            in: fetchedModels,
            existingModelIDs: existingModelIDs,
            filterMode: filterMode,
            searchText: searchText,
            isFullySupported: { isFullySupported($0) }
        )
    }

    private var existingModelsCount: Int {
        FetchedModelsSelectionSupport.existingModelsCount(
            in: fetchedModels,
            existingModelIDs: existingModelIDs
        )
    }

    private var isConfirmDisabled: Bool {
        FetchedModelsSelectionSupport.isConfirmDisabled(
            selectedCount: selectedIDs.count,
            existingModelsCount: existingModelsCount
        )
    }

    // MARK: - Actions

    private func confirmSelection() {
        let selected = fetchedModels.filter { selectedIDs.contains($0.id) }
        onConfirm(selected)
        dismiss()
    }

    private func selectAll(_ models: [ModelInfo]) {
        for model in models {
            selectedIDs.insert(model.id)
        }
    }

    private func deselectAll() {
        selectedIDs.removeAll()
    }

    private func toggleModel(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Resolved once in `init`. This used to scan `fetchedModels` for the model it
    /// was being asked about, and it is called once per model while filtering and
    /// again once per row — quadratic over a provider-sized fetch.
    private func isFullySupported(_ modelID: String) -> Bool {
        fullySupportedModelIDs.contains(modelID)
    }
}
