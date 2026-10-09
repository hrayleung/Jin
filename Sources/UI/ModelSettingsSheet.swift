import SwiftUI

struct ModelSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: ModelInfo
    let providerType: ProviderType?
    let onSave: (ModelInfo) -> Void

    @State private var modelType: ModelType
    @State private var contextWindowText: String
    @State private var maxOutputTokensText: String
    @State private var capabilities: ModelCapability
    @State private var reasoningEnabled: Bool
    @State private var reasoningType: ReasoningConfigType
    @State private var reasoningEffort: ReasoningEffort
    @State private var reasoningBudgetText: String
    @State private var reasoningCanDisable: Bool
    @State private var webSearchSupported: Bool
    @State private var validationError: String?

    init(
        model: ModelInfo,
        providerType: ProviderType?,
        onSave: @escaping (ModelInfo) -> Void
    ) {
        self.model = model
        self.providerType = providerType
        self.onSave = onSave

        let resolved = ModelSettingsResolver.resolve(model: model, providerType: providerType)
        let resolvedReasoning = resolved.reasoningConfig
        let editableReasoning = ModelSettingsSheetSupport.editableReasoningConfig(
            for: model, providerType: providerType
        )
        let initialEffort = editableReasoning.defaultEffort ?? .medium
        let normalizedInitialEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
            initialEffort,
            for: providerType,
            modelID: ModalEndpointSupport.catalogModelID(for: model)
        )

        _modelType = State(initialValue: resolved.modelType)
        _contextWindowText = State(initialValue: "\(resolved.contextWindow)")
        _maxOutputTokensText = State(initialValue: model.overrides?.maxOutputTokens.map(String.init) ?? "")
        _capabilities = State(initialValue: resolved.capabilities)
        _reasoningEnabled = State(initialValue: resolvedReasoning?.type != ReasoningConfigType.none && resolvedReasoning != nil)
        _reasoningType = State(initialValue: editableReasoning.type)
        _reasoningEffort = State(initialValue: normalizedInitialEffort)
        _reasoningBudgetText = State(initialValue: editableReasoning.defaultBudget.map(String.init) ?? "")
        _reasoningCanDisable = State(initialValue: resolved.reasoningCanDisable)
        _webSearchSupported = State(initialValue: resolved.supportsWebSearch)
    }

    var body: some View {
        JinSheet("Model Settings", subtitle: model.name) {
            JinSettingsPage(horizontalPadding: 0, verticalPadding: 0) {
                JinSettingsSection("Model") {
                    if let visibleID = ModalEndpointSupport.userFacingModelID(for: model) {
                        JinSettingsControlRow("Model ID", controlAlignment: .leading) {
                            Text(visibleID)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    JinSettingsPickerRow("Type", selection: $modelType) {
                        ForEach(ModelType.allCases, id: \.self) { type in Text(type.displayName).tag(type) }
                    }
                }
                JinSettingsSection("Token Limits") {
                    JinSettingsTextFieldRow(
                        "Context Window", prompt: "200000", text: $contextWindowText, usesMonospacedFont: true)
                    JinSettingsTextFieldRow(
                        "Max Output", prompt: "Provider default", text: $maxOutputTokensText, usesMonospacedFont: true)
                }
                JinSettingsSection("Capabilities") {
                    JinSettingsToggleRow("Web Search", isOn: $webSearchSupported)
                    JinSettingsToggleRow("Image Input", isOn: capabilityBinding(.vision))
                    JinSettingsToggleRow("Image Output", isOn: capabilityBinding(.imageGeneration))
                    JinSettingsToggleRow("Audio Input", isOn: capabilityBinding(.audio))
                    JinSettingsToggleRow("Video Input", isOn: capabilityBinding(.videoInput))
                    JinSettingsToggleRow("Video Generation", isOn: capabilityBinding(.videoGeneration))
                }
                JinSettingsSection("Reasoning") {
                    JinSettingsToggleRow("Enabled", isOn: $reasoningEnabled)
                    if reasoningEnabled {
                        JinSettingsPickerRow("Mode", selection: $reasoningType) {
                            Text("Effort").tag(ReasoningConfigType.effort)
                            Text("Budget").tag(ReasoningConfigType.budget)
                            Text("Toggle Only").tag(ReasoningConfigType.toggle)
                        }
                        if reasoningType == .effort {
                            JinSettingsPickerRow("Default Effort", selection: $reasoningEffort) {
                                ForEach(availableReasoningEffortLevels, id: \.self) { effort in
                                    Text(effort.displayName).tag(effort)
                                }
                            }
                        } else if reasoningType == .budget {
                            JinSettingsTextFieldRow(
                                "Default Budget", prompt: "1024", text: $reasoningBudgetText, usesMonospacedFont: true)
                        }
                        JinSettingsToggleRow("Allow Disabling per Chat", isOn: $reasoningCanDisable)
                    }
                }
                if let validationError {
                    JinSettingsErrorText(text: validationError)
                }
            }
        } actions: {
            if model.overrides != nil {
                Button("Restore Defaults", action: resetOverrides)
                Spacer()
            }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 620, idealHeight: 700)
    }

    private func capabilityBinding(_ capability: ModelCapability) -> Binding<Bool> {
        Binding(
            get: { capabilities.contains(capability) },
            set: { newValue in
                if newValue { capabilities.insert(capability) } else { capabilities.remove(capability) }
            }
        )
    }

    // MARK: - Helpers

    private var catalogModelID: String {
        ModalEndpointSupport.catalogModelID(for: model)
    }

    private var availableReasoningEffortLevels: [ReasoningEffort] {
        ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: catalogModelID,
            declaredEfforts: model.reasoningConfig?.supportedEfforts
        )
    }

    private func resetOverrides() {
        onSave(
            ModelInfo(
                id: model.id,
                name: model.name,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                maxOutputTokens: model.maxOutputTokens,
                reasoningConfig: model.reasoningConfig,
                overrides: nil,
                catalogMetadata: model.catalogMetadata,
                isEnabled: model.isEnabled
            )
        )
        dismiss()
    }

    private func save() {
        guard let contextWindow = ModelSettingsSheetSupport.positiveInteger(from: contextWindowText) else {
            validationError = "Context length must be a positive integer."
            return
        }

        let maxOutputTokens: Int?
        switch ModelSettingsSheetSupport.optionalPositiveInteger(from: maxOutputTokensText) {
        case .empty:
            maxOutputTokens = nil
        case .value(let value):
            maxOutputTokens = value
        case .invalid:
            validationError = "Max output must be a positive integer."
            return
        }

        var updatedCapabilities = capabilities
        if reasoningEnabled {
            updatedCapabilities.insert(.reasoning)
        } else {
            updatedCapabilities.remove(.reasoning)
        }

        switch modelType {
        case .chat:
            break
        case .image:
            updatedCapabilities.insert(.imageGeneration)
            updatedCapabilities.remove(.videoGeneration)
        case .video:
            updatedCapabilities.insert(.videoGeneration)
            updatedCapabilities.remove(.imageGeneration)
        }

        let reasoningConfig: ModelReasoningConfig?
        if reasoningEnabled {
            switch reasoningType {
            case .effort:
                let normalizedEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
                    reasoningEffort,
                    for: providerType,
                    modelID: catalogModelID
                )
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: normalizedEffort)
            case .budget:
                guard let budget = ModelSettingsSheetSupport.positiveInteger(from: reasoningBudgetText) else {
                    validationError = "Reasoning budget must be a positive integer."
                    return
                }
                reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: budget)
            case .toggle:
                reasoningConfig = ModelReasoningConfig(type: .toggle)
            case .none:
                reasoningConfig = nil
            }
        } else {
            // Explicitly persist "off" when the base model declares reasoning support.
            // Otherwise a nil override falls back to the base reasoning config on reload.
            if model.reasoningConfig != nil {
                reasoningConfig = ModelReasoningConfig(type: .none)
            } else {
                reasoningConfig = nil
            }
        }

        let baseModelType = ModelSettingsResolver.inferModelType(
            capabilities: model.capabilities,
            modelID: catalogModelID
        )
        let baseReasoningCanDisable = ModelSettingsResolver.defaultReasoningCanDisable(
            for: providerType,
            modelID: catalogModelID
        )
        let baseWebSearchSupported = ModelCapabilityRegistry.supportsWebSearch(
            for: providerType,
            modelID: catalogModelID
        )
        let baseMaxOutputTokens = providerType.flatMap {
            ModelCatalog.entry(for: catalogModelID, provider: $0)?.maxOutputTokens
        }

        var overrides = ModelOverrides()
        if modelType != baseModelType {
            overrides.modelType = modelType
        }
        if contextWindow != model.contextWindow {
            overrides.contextWindow = contextWindow
        }
        if let maxOutputTokens, maxOutputTokens != baseMaxOutputTokens {
            overrides.maxOutputTokens = maxOutputTokens
        }
        if updatedCapabilities != model.capabilities {
            overrides.capabilities = updatedCapabilities
        }
        if reasoningConfig != model.reasoningConfig {
            overrides.reasoningConfig = reasoningConfig
        }
        if reasoningCanDisable != baseReasoningCanDisable {
            overrides.reasoningCanDisable = reasoningCanDisable
        }
        if webSearchSupported != baseWebSearchSupported {
            overrides.webSearchSupported = webSearchSupported
        }

        let finalOverrides: ModelOverrides? = overrides.isEmpty ? nil : overrides
        onSave(
            ModelInfo(
                id: model.id,
                name: model.name,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                maxOutputTokens: model.maxOutputTokens,
                reasoningConfig: model.reasoningConfig,
                overrides: finalOverrides,
                catalogMetadata: model.catalogMetadata,
                isEnabled: model.isEnabled
            )
        )
        dismiss()
    }
}

// MARK: - Local helpers

private enum ModelTypeIconography {
    static func glyph(for type: ModelType) -> String {
        switch type {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        }
    }
}
