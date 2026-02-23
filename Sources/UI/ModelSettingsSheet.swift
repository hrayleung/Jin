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
        let initialEffort = resolvedReasoning?.defaultEffort ?? .medium
        let normalizedInitialEffort = ModelCapabilityRegistry.normalizedReasoningEffort(
            initialEffort,
            for: providerType,
            modelID: model.id
        )

        _modelType = State(initialValue: resolved.modelType)
        _contextWindowText = State(initialValue: "\(resolved.contextWindow)")
        _maxOutputTokensText = State(initialValue: resolved.maxOutputTokens.map(String.init) ?? "")
        _capabilities = State(initialValue: resolved.capabilities)
        _reasoningEnabled = State(initialValue: resolvedReasoning?.type != ReasoningConfigType.none && resolvedReasoning != nil)
        _reasoningType = State(initialValue: resolvedReasoning?.type ?? .effort)
        _reasoningEffort = State(initialValue: normalizedInitialEffort)
        _reasoningBudgetText = State(initialValue: resolvedReasoning?.defaultBudget.map(String.init) ?? "")
        _reasoningCanDisable = State(initialValue: resolved.reasoningCanDisable)
        _webSearchSupported = State(initialValue: resolved.supportsWebSearch)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $modelType) {
                        ForEach(ModelType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Token Limits") {
                    TextField("Context length", text: $contextWindowText)
                        .textFieldStyle(.roundedBorder)

                    TextField("Max output", text: $maxOutputTokensText)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Capabilities") {
                    Toggle("Web Search", isOn: $webSearchSupported)
                    capabilityToggle("Image input", capability: .vision)
                    capabilityToggle("Image output", capability: .imageGeneration)
                    capabilityToggle("Audio input", capability: .audio)
                    capabilityToggle("Video generation", capability: .videoGeneration)
                }

                Section("Reasoning") {
                    Toggle("Reasoning model (can output thinking)", isOn: $reasoningEnabled)

                    if reasoningEnabled {
                        Picker("Reasoning mode", selection: $reasoningType) {
                            Text("Reasoning effort").tag(ReasoningConfigType.effort)
                            Text("Reasoning budget").tag(ReasoningConfigType.budget)
                            Text("Toggle only").tag(ReasoningConfigType.toggle)
                        }

                        if reasoningType == .effort {
                            Picker("Default effort", selection: $reasoningEffort) {
                                ForEach(availableReasoningEffortLevels, id: \.self) { effort in
                                    Text(effort.displayName).tag(effort)
                                }
                            }
                        } else if reasoningType == .budget {
                            TextField("Default budget tokens", text: $reasoningBudgetText)
                                .textFieldStyle(.roundedBorder)
                        }

                        Toggle("Can disable reasoning", isOn: $reasoningCanDisable)
                    }
                }

                if let validationError {
                    Section {
                        Text(validationError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Model Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if model.overrides != nil {
                    ToolbarItem(placement: .automatic) {
                        Button("Reset", role: .destructive) {
                            onSave(
                                ModelInfo(
                                    id: model.id,
                                    name: model.name,
                                    capabilities: model.capabilities,
                                    contextWindow: model.contextWindow,
                                    reasoningConfig: model.reasoningConfig,
                                    overrides: nil,
                                    isEnabled: model.isEnabled
                                )
                            )
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 540)
    }

    private func capabilityToggle(_ title: String, capability: ModelCapability) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { capabilities.contains(capability) },
                set: { isOn in
                    if isOn {
                        capabilities.insert(capability)
                    } else {
                        capabilities.remove(capability)
                    }
                }
            )
        )
    }

    private var availableReasoningEffortLevels: [ReasoningEffort] {
        ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: model.id
        )
    }

    private func save() {
        guard let contextWindow = parsedPositiveInt(from: contextWindowText) else {
            validationError = "Context length must be a positive integer."
            return
        }

        let maxOutputTokens = parsedOptionalPositiveInt(from: maxOutputTokensText)
        if !maxOutputTokensText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, maxOutputTokens == nil {
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
                    modelID: model.id
                )
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: normalizedEffort)
            case .budget:
                guard let budget = parsedPositiveInt(from: reasoningBudgetText) else {
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
            modelID: model.id
        )
        let baseReasoningCanDisable = ModelSettingsResolver.defaultReasoningCanDisable(
            for: providerType,
            modelID: model.id
        )
        let baseWebSearchSupported = ModelCapabilityRegistry.supportsWebSearch(
            for: providerType,
            modelID: model.id
        )

        var overrides = ModelOverrides()
        if modelType != baseModelType {
            overrides.modelType = modelType
        }
        if contextWindow != model.contextWindow {
            overrides.contextWindow = contextWindow
        }
        if let maxOutputTokens {
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
                reasoningConfig: model.reasoningConfig,
                overrides: finalOverrides,
                isEnabled: model.isEnabled
            )
        )
        dismiss()
    }

    private func parsedPositiveInt(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private func parsedOptionalPositiveInt(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }
}
