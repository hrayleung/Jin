import SwiftUI

struct FetchedModelsSelectionHeaderBar: View {
    let selectionLabel: String
    @Binding var searchText: String
    @Binding var filterMode: FetchedModelsSelectionFilterMode

    var body: some View {
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
                JinSearchField(text: $searchText, prompt: "Search models", focusesOnAppear: true)

                filterMenu
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, JinSpacing.medium)
    }

    private var filterMenu: some View {
        Menu {
            ForEach(FetchedModelsSelectionFilterMode.allCases, id: \.self) { mode in
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
                Image(systemName: FetchedModelsSelectionSupport.filterIconName(for: filterMode))
                Text(FetchedModelsSelectionSupport.filterButtonTitle(for: filterMode))
                    .lineLimit(1)
            }
            .font(.subheadline)

        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct FetchedModelsSelectionModelListContent: View {
    let fetchedModelsEmpty: Bool
    let models: [ModelInfo]
    let existingModelIDs: Set<String>
    let selectedIDs: Set<String>
    let isFullySupported: (String) -> Bool
    let onToggleModel: (String) -> Void

    var body: some View {
        Group {
            if fetchedModelsEmpty {
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
                            FetchedModelsSelectionModelRow(
                                model: model,
                                isExisting: existingModelIDs.contains(model.id),
                                isSelected: selectedIDs.contains(model.id),
                                isFullySupported: isFullySupported(model.id),
                                onToggle: { onToggleModel(model.id) }
                            )
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
}

struct FetchedModelsSelectionBottomBar: View {
    let confirmButtonLabel: String
    let isConfirmDisabled: Bool
    let isSelectAllDisabled: Bool
    let isDeselectAllDisabled: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu("Selection") {
                Button("Select All", action: onSelectAll).disabled(isSelectAllDisabled)
                Button("Deselect All", action: onDeselectAll).disabled(isDeselectAllDisabled)
            }
            .fixedSize()
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(confirmButtonLabel, action: onConfirm)
                .keyboardShortcut(.defaultAction)
                .disabled(isConfirmDisabled)
        }
        .controlSize(.regular)
        .padding(.horizontal, 20)
        .padding(.vertical, JinSpacing.medium)
    }
}

private struct FetchedModelsSelectionModelRow: View {
    let model: ModelInfo
    let isExisting: Bool
    let isSelected: Bool
    let isFullySupported: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onToggle()
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .opacity(isExisting && !isSelected ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(model.name)\(isExisting ? ", already added" : "")")
    }

    private var rowContent: some View {
        HStack(spacing: JinSpacing.medium) {
            modelIdentity
            existingBadge
            selectionGlyph
        }
        .padding(.horizontal, 20)
        .padding(.vertical, JinSpacing.small)
        .contentShape(Rectangle())
        .background(isHovered ? JinSemanticColor.subtleSurface : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var modelIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            modelTitle

            if let visibleID = ModalEndpointSupport.userFacingModelID(for: model) {
                Text(visibleID)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var modelTitle: some View {
        HStack(spacing: 6) {
            Text(model.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            fullySupportedBadge
        }
    }

    @ViewBuilder
    private var fullySupportedBadge: some View {
        if isFullySupported {
            ModelSupportIndicator()
        }
    }

    @ViewBuilder
    private var existingBadge: some View {
        if isExisting {
            Text("Already added")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var selectionGlyph: some View {
        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .imageScale(.large)
            .accessibilityHidden(true)
    }
}
