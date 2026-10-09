import SwiftUI

extension ProviderConfigFormView {

    @ViewBuilder
    func modelsSection(_ state: ProviderFormSupport.ModelListState) -> some View {
        if let modelsError {
            JinSettingsErrorText(text: modelsError)
        }

        if !state.isEmpty {
            modelSearchRow
            modelActionsRow(state)
        }

        modelsListContent(state)
        modelsFooterActions(state)
    }

    private var modelSearchRow: some View {
        JinSearchField(text: $modelSearchText, prompt: "Search models", chrome: .borderless)
    }

    private func modelActionsRow(_ state: ProviderFormSupport.ModelListState) -> some View {
        HStack(spacing: JinSpacing.small) {
            Text("Enabled \(state.summary.enabledCount) / \(state.summary.totalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Enable All") {
                setAllModelsEnabled(true)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            Divider().frame(height: 12)

            Button("Disable All") {
                setAllModelsEnabled(false)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            Divider().frame(height: 12)

            modelFilterActionsMenu(state)
        }
    }

    private func modelFilterActionsMenu(_ state: ProviderFormSupport.ModelListState) -> some View {
        Menu {
            Button {
                showingKeepFullySupportedModelsConfirmation = true
            } label: {
                Label("Keep Fully Supported", systemImage: "checkmark.seal")
            }
            .disabled(!state.canKeepFullySupportedModels)

            Button {
                showingKeepEnabledModelsConfirmation = true
            } label: {
                Label("Keep Enabled Only", systemImage: "power")
            }
            .disabled(!state.canKeepEnabledModels)
            Divider()
            Button("Delete All Models…", role: .destructive) {
                showingDeleteAllModelsConfirmation = true
            }
            .disabled(state.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .help("Filter actions")
        .accessibilityLabel("Filter actions")
    }

    @ViewBuilder
    private func modelsListContent(_ state: ProviderFormSupport.ModelListState) -> some View {
        if state.isEmpty {
            Text(
                providerType == .modal
                    ? "No endpoints yet."
                    : "No models found. Fetch from provider or add manually."
            )
                .jinInfoCallout()
        } else if state.filteredModels.isEmpty {
            Text("No models match your search.")
                .jinInfoCallout()
        } else {
            // Deliberately a ScrollView + LazyVStack, not a `List`.
            //
            // A `List` nested in a grouped `Form` builds a `ListCoreScrollView` with
            // `hasVerticalScroller == false` that refuses scroll wheel events outright
            // — handing one straight to `scrollWheel(with:)` does not move it. That was
            // survivable while the list was `minHeight`-only, because it grew to its
            // full content height and the Form's own scroll view carried the user past
            // the overflow. Bounding it to `modelListHeight` (needed so rows virtualize)
            // shrank the Form back under one screen, so the only surface with hidden
            // content became the one that cannot scroll: with 64 models you could see
            // seven and reach none of the rest.
            //
            // `LazyVStack` keeps the virtualization the bound was introduced for — at
            // 435 models it is materially cheaper than the `List` it replaces (37 ms vs
            // 114 ms first layout, 34 vs 94 live NSViews) — and its `HostingScrollView`
            // takes the wheel normally.
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(state.filteredModels) { model in
                        ProviderModelListRow(
                            model: model,
                            isFullySupported: state.fullySupportedModelIDs.contains(model.id),
                            isEnabled: modelEnabledBinding(
                                modelID: model.id,
                                enabledByModelID: state.enabledByModelID
                            ),
                            onEdit: { editingModel = model },
                            onDelete: { requestDeleteModel(model) }
                        )
                        .padding(.vertical, JinSpacing.xSmall)

                        if model.id != state.lastFilteredModelID {
                            Divider()
                        }
                    }
                }
            }
            .frame(height: ProviderFormSupport.modelListHeight)
            // The grouped Section card is the only surface. A second fill/outline
            // punches a darker well through the card in dark mode.
            .scrollContentBackground(.hidden)
        }
    }

    private func modelsFooterActions(_ state: ProviderFormSupport.ModelListState) -> some View {
        HStack(spacing: 8) {
            Button(isFetchingModels ? "Fetching…" : "Fetch Models") {
                Task { await fetchModels() }
            }
            .disabled(isFetchModelsDisabled)
            if isFetchingModels { ProgressView().controlSize(.small) }
            Spacer(minLength: 8)
            if providerType == .modal {
                Menu("Add") {
                    Button("Add Endpoint…") { showingAddEndpoint = true }
                    Button("Add Model…") { showingAddModel = true }
                }
                .fixedSize()
            } else {
                Button("Add Model…") { showingAddModel = true }
            }
        }
    }

}

private struct ProviderModelListRow: View {
    let model: ModelInfo
    let isFullySupported: Bool
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .lineLimit(1)

                    if isFullySupported {
                        ModelSupportIndicator()
                    }

                    if model.overrides != nil {
                        Text("Custom")
                            .jinTagStyle(foreground: .orange)
                            .help("This model has manual capability overrides.")
                    }

                    if ModalEndpointSupport.isAutoEndpointModel(model) {
                        Text("Endpoint")
                            .jinTagStyle(foreground: .accentColor)
                            .help("Deployed as its own Modal endpoint.")
                    }
                }

                if let visibleID = ModalEndpointSupport.userFacingModelID(for: model) {
                    Text(visibleID)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            ProviderModelActionButton(
                systemImage: "slider.horizontal.3",
                help: "Model Settings",
                isVisible: isHovered,
                action: onEdit
            )
            ProviderModelActionButton(
                systemImage: "trash",
                help: "Delete Model",
                role: .destructive,
                isVisible: isHovered,
                action: onDelete
            )

            Toggle("Enable \(model.name)", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onHover { isHovered = $0 }
    }
}

private struct ProviderModelActionButton: View {
    private let systemImage: String
    private let help: String
    private let role: ButtonRole?
    private let isVisible: Bool
    private let action: () -> Void
    @FocusState private var isFocused: Bool

    init(
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        isVisible: Bool,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.help = help
        self.role = role
        self.isVisible = isVisible
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .focused($isFocused)
        .opacity(isVisible || isFocused ? 1 : 0)
    }
}
