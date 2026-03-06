import SwiftUI

struct FetchedModelsSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let fetchedModels: [ModelInfo]
    let existingModelIDs: Set<String>
    let providerType: ProviderType?
    let onConfirm: ([ModelInfo]) -> Void

    @State private var selectedIDs: Set<String> = []
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case fullySupported = "Fully Supported"
        case newOnly = "New Only"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                Divider()
                modelList
                Divider()
                footerBar
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle("Select Models to Add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        let selected = fetchedModels.filter { selectedIDs.contains($0.id) }
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: JinSpacing.medium) {
            HStack(spacing: JinSpacing.medium) {
                Text("\(selectedIDs.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            HStack(spacing: JinSpacing.small) {
                Picker("Filter", selection: $filterMode) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                Button("Select All") {
                    selectAllVisible()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Divider().frame(height: 12)

                Button("Deselect All") {
                    deselectAllVisible()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    // MARK: - Model List

    private var modelList: some View {
        Group {
            if visibleModels.isEmpty {
                ContentUnavailableView {
                    Label("No models match", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term or filter.")
                }
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
        let alreadyAdded = existingModelIDs.contains(model.id)
        let isSelected = selectedIDs.contains(model.id)
        let fullySupported = isFullySupported(model.id)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .lineLimit(1)

                    if fullySupported {
                        Text(JinModelSupport.fullSupportSymbol)
                            .jinTagStyle(foreground: .green)
                            .help("Jin full support")
                    }
                }

                Text(model.id)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if alreadyAdded {
                Text("Already added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { newValue in
                    if newValue {
                        selectedIDs.insert(model.id)
                    } else {
                        selectedIDs.remove(model.id)
                    }
                }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedIDs.remove(model.id)
            } else {
                selectedIDs.insert(model.id)
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: JinSpacing.medium) {
            Group {
                Text("\(fetchedModels.count) fetched")
                if fullySupportedCount > 0 {
                    Text("\(fullySupportedCount) fully supported")
                        .foregroundStyle(.green)
                }
                if newModelsCount > 0 {
                    Text("\(newModelsCount) new")
                        .foregroundStyle(.blue)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Select New Only") {
                selectedIDs = Set(fetchedModels.filter { !existingModelIDs.contains($0.id) }.map(\.id))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(newModelsCount == 0)

            if fullySupportedCount > 0 {
                Divider().frame(height: 12)

                Button("Select Fully Supported") {
                    selectedIDs = Set(fetchedModels.filter { isFullySupported($0.id) }.map(\.id))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    // MARK: - Filtering

    private var visibleModels: [ModelInfo] {
        let baseFiltered: [ModelInfo]
        switch filterMode {
        case .all:
            baseFiltered = fetchedModels
        case .fullySupported:
            baseFiltered = fetchedModels.filter { isFullySupported($0.id) }
        case .newOnly:
            baseFiltered = fetchedModels.filter { !existingModelIDs.contains($0.id) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return baseFiltered }

        return baseFiltered.filter { model in
            model.name.lowercased().contains(query) || model.id.lowercased().contains(query)
        }
    }

    // MARK: - Counts

    private var fullySupportedCount: Int {
        fetchedModels.filter { isFullySupported($0.id) }.count
    }

    private var newModelsCount: Int {
        fetchedModels.filter { !existingModelIDs.contains($0.id) }.count
    }

    // MARK: - Actions

    private func selectAllVisible() {
        for model in visibleModels {
            selectedIDs.insert(model.id)
        }
    }

    private func deselectAllVisible() {
        let visibleIDs = Set(visibleModels.map(\.id))
        selectedIDs.subtract(visibleIDs)
    }

    private func isFullySupported(_ modelID: String) -> Bool {
        guard let providerType else { return false }
        return JinModelSupport.isFullySupported(providerType: providerType, modelID: modelID)
    }
}
