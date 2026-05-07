import SwiftUI

extension ProviderConfigFormView {

    @ViewBuilder
    var modelsSection: some View {
        if let modelsError {
            JinSettingsErrorText(text: modelsError)
        }

        if !decodedModels.isEmpty {
            modelsSearchAndActionsHeader
        }

        modelsListContent
        modelsFooterActions
    }

    private var modelsSearchAndActionsHeader: some View {
        VStack(spacing: JinSpacing.small) {
            TextField("Search models", text: $modelSearchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: JinSpacing.small) {
                Text("Enabled \(enabledModelCount) / \(decodedModels.count)")
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

                modelFilterActionsMenu
            }
        }
    }

    private var modelFilterActionsMenu: some View {
        Menu {
            Button {
                showingKeepFullySupportedModelsConfirmation = true
            } label: {
                Label("Keep Fully Supported", systemImage: "checkmark.seal")
            }
            .disabled(!canKeepFullySupportedModels)

            Button {
                showingKeepEnabledModelsConfirmation = true
            } label: {
                Label("Keep Enabled Only", systemImage: "power")
            }
            .disabled(!canKeepEnabledModels)
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .help("Filter actions")
        .accessibilityLabel("Filter actions")
    }

    @ViewBuilder
    private var modelsListContent: some View {
        if decodedModels.isEmpty {
            Text("No models found. Fetch from provider or add manually.")
                .jinInfoCallout()
        } else if filteredModels.isEmpty {
            Text("No models match your search.")
                .jinInfoCallout()
        } else {
            List(filteredModels) { model in
                modelListRow(model)
            }
            .frame(minHeight: 180)
            .scrollContentBackground(.hidden)
            .background(JinSemanticColor.detailSurface)
            .jinSurface(.outlined, cornerRadius: JinRadius.medium)
        }
    }

    private func modelListRow(_ model: ModelInfo) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .lineLimit(1)

                    if isFullySupportedModel(model.id) {
                        Text(JinModelSupport.fullSupportSymbol)
                            .jinTagStyle(foreground: .green)
                            .help("Jin full support")
                    }

                    if model.overrides != nil {
                        Text("Custom")
                            .jinTagStyle(foreground: .orange)
                            .help("This model has manual capability overrides.")
                    }
                }

                Text(model.id)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer(minLength: 8)

            modelSettingsButton(model)
            deleteModelButton(model)

            Toggle("", isOn: modelEnabledBinding(modelID: model.id))
                .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingModel = model
        }
        .onHover { isHovered in
            if isHovered {
                hoveredModelID = model.id
            } else if hoveredModelID == model.id {
                hoveredModelID = nil
            }
        }
    }

    private func modelSettingsButton(_ model: ModelInfo) -> some View {
        ProviderModelActionButton(
            systemImage: "slider.horizontal.3",
            help: "Model Settings",
            isVisible: hoveredModelID == model.id
        ) {
            editingModel = model
        }
    }

    private func deleteModelButton(_ model: ModelInfo) -> some View {
        ProviderModelActionButton(
            systemImage: "trash",
            help: "Delete Model",
            role: .destructive,
            isVisible: hoveredModelID == model.id
        ) {
            requestDeleteModel(model)
        }
    }

    private var modelsFooterActions: some View {
        HStack {
            Button("Fetch from Provider") {
                Task { await fetchModels() }
            }
            .disabled(isFetchModelsDisabled)

            if isFetchingModels {
                ProgressView().scaleEffect(0.5)
            }

            Spacer()

            Button {
                showingAddModel = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Button {
                showingDeleteAllModelsConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(decodedModels.isEmpty)
            .buttonStyle(.borderless)
        }
    }
}

private struct ProviderModelActionButton: View {
    private let systemImage: String
    private let help: String
    private let role: ButtonRole?
    private let isVisible: Bool
    private let action: () -> Void

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
        .opacity(isVisible ? 1 : 0)
    }
}
