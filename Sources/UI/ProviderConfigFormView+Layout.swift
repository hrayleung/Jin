import SwiftUI

extension ProviderConfigFormView {

    var body: some View {
        providerFormPresentations(
            providerFormLifecycle(
                providerFormPage.navigationTitle(provider.name)
            )
        )
    }

    var providerFormPage: some View {
        JinSettingsPage(maxWidth: providerType == .vertexai ? 820 : 760) {
            providerConfigurationSection
            providerSecondarySection
        }
    }

    private var providerConfigurationSection: some View {
        JinSettingsSection("Configuration") {
            enabledRow
            nameRow
            iconRow
            apiBaseURLRows
            credentialRows

            if providerType == .openrouter {
                openRouterUsageSection
            }

            if let credentialSaveError {
                JinSettingsErrorText(text: credentialSaveError)
            }

            testConnectionButton
        }
    }

    private var enabledRow: some View {
        JinSettingsToggleRow(
            "Enabled",
            isOn: Binding(
                get: { provider.isEnabled },
                set: { newValue in
                    provider.isEnabled = newValue
                    try? modelContext.save()
                }
            )
        )
    }

    private var nameRow: some View {
        JinSettingsControlRow("Name") {
            TextField("Provider name", text: $provider.name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: provider.name) { _, _ in try? modelContext.save() }
        }
    }

    private var iconRow: some View {
        JinSettingsControlRow("Icon") {
            ProviderIconPickerField(
                selectedIconID: Binding(
                    get: { provider.iconID },
                    set: { newValue in
                        provider.iconID = ProviderFormSupport.normalizedIconID(newValue)
                        try? modelContext.save()
                    }
                ),
                defaultIconID: providerType.map { LobeProviderIconCatalog.defaultIconID(for: $0) }
            )
        }
    }

    @ViewBuilder
    private var apiBaseURLRows: some View {
        if let providerType, let defaultBaseURL = providerType.defaultBaseURL {
            JinSettingsControlRow("API Base URL", supportingText: "Use the provider default unless you need a custom endpoint.") {
                HStack(alignment: .center, spacing: JinSpacing.small) {
                    JinSettingsTextField(
                        "API Base URL",
                        text: baseURLBinding(defaultBaseURL: defaultBaseURL),
                        usesMonospacedFont: true
                    )

                    Button("Reset") {
                        provider.baseURL = defaultBaseURL
                        try? modelContext.save()
                    }
                    .disabled((provider.baseURL ?? defaultBaseURL) == defaultBaseURL)
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            if providerType == .cerebras {
                let base = (provider.baseURL ?? defaultBaseURL).lowercased()
                if base.contains("cerebras-sandbox.net") {
                    Text("Warning: cerebras-sandbox.net is the web sandbox and is Cloudflare-protected. Use the API endpoint https://api.cerebras.ai/v1 instead.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var credentialRows: some View {
        if let providerType {
            switch ProviderFormSupport.credentialKind(for: providerType) {
            case .apiKey:
                apiKeyField
            case .serviceAccountJSON:
                vertexAISection
            }
        } else {
            Text("Unknown provider type")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var providerSecondarySection: some View {
        if providerType == .claudeManagedAgents {
            JinSettingsSection("Managed Defaults") {
                claudeManagedDefaultsSection
            }
        } else {
            JinSettingsSection("Models", style: .plain) {
                modelsSection
            }
            .animation(.easeInOut(duration: 0.18), value: filteredModels.count)
            .animation(.easeInOut(duration: 0.18), value: modelSearchText)
        }
    }

    func baseURLBinding(defaultBaseURL: String) -> Binding<String> {
        Binding(
            get: { provider.baseURL ?? defaultBaseURL },
            set: { newValue in
                provider.baseURL = ProviderFormSupport.baseURLForEditing(newValue, defaultBaseURL: defaultBaseURL)
                try? modelContext.save()
            }
        )
    }
}
