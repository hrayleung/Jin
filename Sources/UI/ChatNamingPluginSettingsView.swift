import SwiftUI
import SwiftData

struct ChatNamingPluginSettingsView: View {
    @Query(sort: \ProviderConfigEntity.name) private var providers: [ProviderConfigEntity]

    @AppStorage(AppPreferenceKeys.chatNamingMode) private var chatNamingMode: ChatNamingMode = .firstRoundFixed
    @AppStorage(AppPreferenceKeys.chatNamingProviderID) private var chatNamingProviderID = ""
    @AppStorage(AppPreferenceKeys.chatNamingModelID) private var chatNamingModelID = ""

    var body: some View {
        JinSettingsPage {
            JinSettingsSection("Behavior") {
                Picker("Rename Mode", selection: $chatNamingMode) {
                    ForEach(ChatNamingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            JinSettingsSection(
                "Naming Model",
                detail: "Choose the provider and model used when Jin suggests chat titles."
            ) {
                if allProviderModelPairs.isEmpty {
                    Text("No providers with chat-capable models found. Add or enable a chat model under Settings → Providers.")
                        .jinInfoCallout()
                } else {
                    Picker("Provider", selection: $chatNamingProviderID) {
                        ForEach(providerOptions, id: \.id) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .onChange(of: chatNamingProviderID) { _, _ in
                        ensureValidSelection()
                    }

                    let models = modelsForSelectedProvider
                    if !models.isEmpty {
                        Picker("Model", selection: $chatNamingModelID) {
                            ForEach(models) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .onChange(of: chatNamingModelID) { _, _ in
                            ensureValidSelection()
                        }
                    }
                }
            }
        }
        .navigationTitle("Chat Naming")
        .onAppear {
            ensureValidSelection()
        }
        .onChange(of: providers.count) { _, _ in
            ensureValidSelection()
        }
    }

    private var providerOptions: [ProviderOption] {
        providers
            .filter(\.isEnabled)
            .compactMap { provider in
                let models = chatNamingModels(for: provider)
                guard !models.isEmpty else {
                    return nil
                }

                return ProviderOption(id: provider.id, name: provider.name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var modelsForSelectedProvider: [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == chatNamingProviderID }) else {
            return []
        }
        return chatNamingModels(for: provider)
    }

    private var allProviderModelPairs: [(providerID: String, modelID: String)] {
        providerOptions.flatMap { provider in
            let models = decodedModels(forProviderID: provider.id)
            return models.map { (provider.id, $0.id) }
        }
    }

    private func decodedModels(forProviderID providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return []
        }
        return chatNamingModels(for: provider)
    }

    private func chatNamingModels(for provider: ProviderConfigEntity) -> [ModelInfo] {
        ChatNamingModelSupport.supportedModels(
            from: provider.enabledModels,
            providerType: ProviderType(rawValue: provider.typeRaw)
        )
    }

    private func ensureValidSelection() {
        guard !providerOptions.isEmpty else {
            chatNamingProviderID = ""
            chatNamingModelID = ""
            return
        }

        if !providerOptions.contains(where: { $0.id == chatNamingProviderID }) {
            chatNamingProviderID = providerOptions.first?.id ?? ""
        }

        let models = modelsForSelectedProvider
        if models.isEmpty {
            chatNamingModelID = ""
            return
        }

        if !models.contains(where: { $0.id == chatNamingModelID }) {
            chatNamingModelID = models.first?.id ?? ""
        }
    }
}

private struct ProviderOption: Identifiable {
    let id: String
    let name: String
}
