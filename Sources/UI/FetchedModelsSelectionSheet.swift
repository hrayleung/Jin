import SwiftUI

struct FetchedModelsSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let fetchedModels: [ModelInfo]
    let existingModelIDs: Set<String>
    let providerType: ProviderType?
    let onConfirm: ([ModelInfo]) -> Void

    @State private var selectedIDs: Set<String>
    @State private var searchText: String
    @State private var showFilter: ShowFilter

    enum ShowFilter: String, CaseIterable {
        case newOnly = "New"
        case all = "All"
        case supported = "Supported"
        case existing = "Existing"
    }

    init(
        fetchedModels: [ModelInfo],
        existingModelIDs: Set<String>,
        providerType: ProviderType?,
        onConfirm: @escaping ([ModelInfo]) -> Void
    ) {
        self.fetchedModels = fetchedModels
        self.existingModelIDs = existingModelIDs
        self.providerType = providerType
        self.onConfirm = onConfirm

        let newModelIDs = Set(fetchedModels.lazy.filter { !existingModelIDs.contains($0.id) }.map(\.id))
        _selectedIDs = State(initialValue: newModelIDs)
        _searchText = State(initialValue: "")
        _showFilter = State(initialValue: newModelIDs.isEmpty ? .all : .newOnly)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlsArea
                Divider()
                modelList
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle("Add Models")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) {
                        let selected = fetchedModels.filter { selectedIDs.contains($0.id) }
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty && existingModelsCount == 0)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - Controls

    private var controlsArea: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            TextField("Search models", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("Show", selection: $showFilter) {
                ForEach(ShowFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                Text(statsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer(minLength: 0)

                Menu("Selection") {
                    Button("Select Filtered") { selectAllFiltered() }
                        .disabled(visibleModels.isEmpty)
                    Button("Select New") { selectNewModels() }
                        .disabled(newModelsCount == 0)
                    Divider()
                    Button("Clear Selection") { clearSelection() }
                        .disabled(selectedIDs.isEmpty)
                }
                .controlSize(.small)
            }

            Text(selectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if hiddenSelectedCount > 0 {
                Text("\(hiddenSelectedCount) selected model(s) are hidden by the current filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("New models are preselected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    // MARK: - Model List

    private var modelList: some View {
        Group {
            if fetchedModels.isEmpty {
                ContentUnavailableView {
                    Label("No models returned", systemImage: "tray")
                } description: {
                    Text("This provider did not return models for the current credentials.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleModels.isEmpty {
                ContentUnavailableView {
                    Label("No models match", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term or filter.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleModels) { model in
                    modelRow(model)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func modelRow(_ model: ModelInfo) -> some View {
        let existing = existingModelIDs.contains(model.id)
        let supported = isFullySupported(model.id)

        return Toggle(isOn: toggleBinding(for: model.id)) {
            HStack(spacing: JinSpacing.small) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .lineLimit(1)

                        Text(existing ? "Existing" : "New")
                            .font(.caption)
                            .foregroundStyle(existing ? Color.secondary : Color.accentColor)

                        if supported {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .help("Jin full support")
                        }
                    }

                    Text(model.id)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if selectedIDs.contains(model.id) {
                    Text(existing ? "Update" : "Add")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Computed

    private var confirmLabel: String {
        if selectedIDs.isEmpty {
            return existingModelsCount > 0 ? "Refresh Existing" : "Add"
        }
        return "Add Selected (\(selectedIDs.count))"
    }

    private var statsSummary: String {
        "\(totalFetchedCount) fetched, \(newModelsCount) new, \(existingModelsCount) existing, \(supportedModelsCount) supported"
    }

    private var selectionSummary: String {
        if selectedIDs.isEmpty {
            return "No selection"
        }

        var parts: [String] = []
        if selectedNewCount > 0 {
            parts.append("\(selectedNewCount) new")
        }
        if selectedExistingCount > 0 {
            parts.append("\(selectedExistingCount) existing")
        }

        if hiddenSelectedCount > 0 {
            return "\(parts.joined(separator: ", ")) selected (\(hiddenSelectedCount) hidden)"
        }
        return "\(parts.joined(separator: ", ")) selected"
    }

    private var visibleModels: [ModelInfo] {
        let base: [ModelInfo]
        switch showFilter {
        case .newOnly:
            base = orderedModels.filter { !existingModelIDs.contains($0.id) }
        case .all:
            base = orderedModels
        case .supported:
            base = orderedModels.filter { isFullySupported($0.id) }
        case .existing:
            base = orderedModels.filter { existingModelIDs.contains($0.id) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }

        return base.filter { model in
            model.name.lowercased().contains(query) || model.id.lowercased().contains(query)
        }
    }

    private var orderedModels: [ModelInfo] {
        fetchedModels.sorted { lhs, rhs in
            let lhsExisting = existingModelIDs.contains(lhs.id)
            let rhsExisting = existingModelIDs.contains(rhs.id)
            if lhsExisting != rhsExisting {
                return !lhsExisting && rhsExisting
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var totalFetchedCount: Int {
        fetchedModels.count
    }

    private var newModelsCount: Int {
        fetchedModels.filter { !existingModelIDs.contains($0.id) }.count
    }

    private var existingModelsCount: Int {
        fetchedModels.count - newModelsCount
    }

    private var supportedModelsCount: Int {
        fetchedModels.filter { isFullySupported($0.id) }.count
    }

    private var selectedVisibleCount: Int {
        visibleModels.reduce(into: 0) { count, model in
            if selectedIDs.contains(model.id) {
                count += 1
            }
        }
    }

    private var hiddenSelectedCount: Int {
        max(selectedIDs.count - selectedVisibleCount, 0)
    }

    private var selectedExistingCount: Int {
        selectedIDs.reduce(into: 0) { count, modelID in
            if existingModelIDs.contains(modelID) {
                count += 1
            }
        }
    }

    private var selectedNewCount: Int {
        max(selectedIDs.count - selectedExistingCount, 0)
    }

    // MARK: - Actions

    private func selectAllFiltered() {
        for model in visibleModels {
            selectedIDs.insert(model.id)
        }
    }

    private func selectNewModels() {
        let newIDs = fetchedModels.compactMap { model in
            existingModelIDs.contains(model.id) ? nil : model.id
        }
        selectedIDs = Set(newIDs)
    }

    private func clearSelection() {
        selectedIDs.removeAll()
    }

    private func toggleBinding(for modelID: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(modelID) },
            set: { selected in
                if selected {
                    selectedIDs.insert(modelID)
                } else {
                    selectedIDs.remove(modelID)
                }
            }
        )
    }

    private func isFullySupported(_ modelID: String) -> Bool {
        guard let providerType else { return false }
        return JinModelSupport.isFullySupported(providerType: providerType, modelID: modelID)
    }
}
