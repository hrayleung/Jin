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
        case all = "All Models"
        case new = "New Only"
        case supported = "Fully Supported"
        case existing = "Already Added"
    }

    var body: some View {
        let models = visibleModels
        VStack(spacing: 0) {
            headerBar
            Divider()
            modelListContent(models)
            Divider()
            bottomBar(models)
        }
        .background(JinSemanticColor.detailSurface)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 480, idealHeight: 560)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: JinSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Select models to add")
                    .font(.headline)

                Spacer()

                Text(selectionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: JinSpacing.small) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, JinSpacing.small)
                .padding(.vertical, 6)
                .background(JinSemanticColor.subtleSurface, in: RoundedRectangle(cornerRadius: JinRadius.small))

                filterMenu
            }
        }
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    private var filterMenu: some View {
        Menu {
            ForEach(FilterMode.allCases, id: \.self) { mode in
                Button {
                    filterMode = mode
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        if mode == filterMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filterIcon)
                Text(filterMode == .all ? "Filter" : filterMode.rawValue)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .background(
                filterMode == .all
                    ? JinSemanticColor.subtleSurface
                    : JinSemanticColor.accentSurface,
                in: RoundedRectangle(cornerRadius: JinRadius.small)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var filterIcon: String {
        filterMode == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
    }

    // MARK: - Model List

    private func modelListContent(_ models: [ModelInfo]) -> some View {
        Group {
            if fetchedModels.isEmpty {
                ContentUnavailableView {
                    Label("No models returned", systemImage: "tray")
                } description: {
                    Text("This provider did not return any models.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if models.isEmpty {
                ContentUnavailableView {
                    Label("No models match", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term or filter.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let lastID = models.last?.id
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(models) { model in
                            modelRow(model)
                            if model.id != lastID {
                                Divider()
                                    .padding(.leading, JinSpacing.large)
                            }
                        }
                    }
                }
            }
        }
    }

    private func modelRow(_ model: ModelInfo) -> some View {
        let isExisting = existingModelIDs.contains(model.id)
        let isSelected = selectedIDs.contains(model.id)
        let supported = isFullySupported(model.id)

        return Button {
            toggleModel(model.id)
        } label: {
            HStack(spacing: JinSpacing.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if supported {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .help("Fully supported by Jin")
                        }
                    }

                    Text(model.id)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                if isExisting {
                    Text("Already added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                Toggle(model.name, isOn: toggleBinding(for: model.id))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .padding(.horizontal, JinSpacing.large)
            .padding(.vertical, JinSpacing.small)
            .contentShape(Rectangle())
            .background(isSelected ? JinSemanticColor.selectedSurface : Color.clear)
        }
        .buttonStyle(.plain)
        .opacity(isExisting && !isSelected ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(model.name)\(isExisting ? ", already added" : "")")
    }

    // MARK: - Bottom Bar

    private func bottomBar(_ models: [ModelInfo]) -> some View {
        HStack {
            Button(confirmButtonLabel) {
                let selected = fetchedModels.filter { selectedIDs.contains($0.id) }
                onConfirm(selected)
                dismiss()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(selectedIDs.isEmpty && existingModelsCount == 0)

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button("Select All") {
                for model in models { selectedIDs.insert(model.id) }
            }
            .disabled(models.allSatisfy { selectedIDs.contains($0.id) })

            Button("Deselect All") { selectedIDs.removeAll() }
                .disabled(selectedIDs.isEmpty)
        }
        .controlSize(.regular)
        .padding(.horizontal, JinSpacing.large)
        .padding(.vertical, JinSpacing.medium)
    }

    // MARK: - Labels

    private var selectionLabel: String {
        "\(selectedIDs.count) selected"
    }

    private var confirmButtonLabel: String {
        selectedIDs.isEmpty ? "Confirm" : "Confirm (\(selectedIDs.count))"
    }

    // MARK: - Computed

    private var visibleModels: [ModelInfo] {
        let filtered: [ModelInfo]
        switch filterMode {
        case .all:
            filtered = orderedModels
        case .new:
            filtered = orderedModels.filter { !existingModelIDs.contains($0.id) }
        case .supported:
            filtered = orderedModels.filter { isFullySupported($0.id) }
        case .existing:
            filtered = orderedModels.filter { existingModelIDs.contains($0.id) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return filtered }
        return filtered.filter { $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query) }
    }

    private var orderedModels: [ModelInfo] {
        fetchedModels.sorted { lhs, rhs in
            let lhsExisting = existingModelIDs.contains(lhs.id)
            let rhsExisting = existingModelIDs.contains(rhs.id)
            if lhsExisting != rhsExisting {
                return !lhsExisting
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var existingModelsCount: Int {
        fetchedModels.filter { existingModelIDs.contains($0.id) }.count
    }

    // MARK: - Actions

    private func toggleModel(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
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
