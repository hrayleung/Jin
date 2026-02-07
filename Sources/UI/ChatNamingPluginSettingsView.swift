import SwiftUI
import SwiftData

struct ChatNamingPluginSettingsView: View {
    @Query(sort: \ProviderConfigEntity.name) private var providers: [ProviderConfigEntity]

    @AppStorage(AppPreferenceKeys.chatNamingMode) private var chatNamingMode: ChatNamingMode = .firstRoundFixed
    @AppStorage(AppPreferenceKeys.chatNamingProviderID) private var chatNamingProviderID = ""
    @AppStorage(AppPreferenceKeys.chatNamingModelID) private var chatNamingModelID = ""

    var body: some View {
        Form {
            Section("Chat Naming") {
                Text("Use a selected model to automatically generate concise chat titles.")
                    .jinInfoCallout()
            }

            Section("Behavior") {
                Picker("Rename Mode", selection: $chatNamingMode) {
                    ForEach(ChatNamingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("Naming Model") {
                if allProviderModelPairs.isEmpty {
                    Text("No providers with models found. Add models under Settings → Providers.")
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
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
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
            .compactMap { provider in
                guard let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData),
                      !models.isEmpty else {
                    return nil
                }

                return ProviderOption(id: provider.id, name: provider.name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var modelsForSelectedProvider: [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == chatNamingProviderID }),
              let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData) else {
            return []
        }
        return models
    }

    private var allProviderModelPairs: [(providerID: String, modelID: String)] {
        providerOptions.flatMap { provider in
            let models = decodedModels(forProviderID: provider.id)
            return models.map { (provider.id, $0.id) }
        }
    }

    private func decodedModels(forProviderID providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }),
              let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData) else {
            return []
        }
        return models
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
