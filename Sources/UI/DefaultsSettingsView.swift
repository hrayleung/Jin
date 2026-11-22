import SwiftUI
import SwiftData

struct DefaultsSettingsView: View {
    @Query(sort: \ProviderConfigEntity.name) private var providers: [ProviderConfigEntity]
    @Query(sort: \MCPServerConfigEntity.name) private var mcpServers: [MCPServerConfigEntity]

    @AppStorage(AppPreferenceKeys.newChatModelMode) private var newChatModelMode: NewChatModelMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedProviderID) private var newChatFixedProviderID = "openai"
    @AppStorage(AppPreferenceKeys.newChatFixedModelID) private var newChatFixedModelID = "gpt-5.2"
    @AppStorage(AppPreferenceKeys.newChatMCPMode) private var newChatMCPMode: NewChatMCPMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedMCPEnabled) private var newChatFixedMCPEnabled = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPUseAllServers) private var newChatFixedMCPUseAllServers = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPServerIDsJSON) private var newChatFixedMCPServerIDsJSON = "[]"

    var body: some View {
        JinSettingsPage(title: "Defaults") {
            JinSettingsSection("Model") {
                JinSettingsPickerRow("New chats start with", selection: $newChatModelMode) {
                    ForEach(NewChatModelMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if newChatModelMode == .fixed {
                    JinSettingsPickerRow("Provider", selection: $newChatFixedProviderID) {
                        ForEach(providers.filter(\.isEnabled), id: \.id) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .onChange(of: newChatFixedProviderID) { _, _ in
                        ensureValidFixedModelSelection()
                    }

                    let models = modelsForProvider(newChatFixedProviderID)
                    if models.isEmpty {
                        JinSettingsControlRow("Model") {
                            Text("No models for this provider")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        JinSettingsPickerRow("Model", selection: $newChatFixedModelID) {
                            ForEach(models) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .onChange(of: newChatFixedModelID) { _, _ in
                            ensureValidFixedModelSelection()
                        }
                    }
                }
            }

            JinSettingsSection("MCP Tools") {
                JinSettingsPickerRow("New chats start with", selection: $newChatMCPMode) {
                    ForEach(NewChatMCPMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if newChatMCPMode == .fixed {
                    JinSettingsToggleRow("Turn on MCP tools", isOn: $newChatFixedMCPEnabled)

                    if newChatFixedMCPEnabled {
                        JinSettingsToggleRow("Use every enabled server", isOn: $newChatFixedMCPUseAllServers)
                            .onChange(of: newChatFixedMCPUseAllServers) { _, isOn in
                                guard !isOn else { return }
                                let current = AppPreferences.decodeStringArrayJSON(newChatFixedMCPServerIDsJSON)
                                guard current.isEmpty else { return }
                                let eligibleIDs = eligibleMCPServers.map(\.id)
                                newChatFixedMCPServerIDsJSON = AppPreferences.encodeStringArrayJSON(eligibleIDs)
                            }
                    }
                }
            }

            if showsFixedMCPServerList {
                fixedMCPServersSection
            }
        }
        .onAppear {
            ensureValidFixedModelSelection()
        }
    }

    private var showsFixedMCPServerList: Bool {
        newChatMCPMode == .fixed && newChatFixedMCPEnabled && !newChatFixedMCPUseAllServers
    }

    @ViewBuilder
    private var fixedMCPServersSection: some View {
        let eligibleServers = eligibleMCPServers
        JinSettingsSection(
            "Servers",
            detail: eligibleServers.isEmpty
                ? "Only enabled servers that run tools automatically can be chosen. Set one up in MCP Servers."
                : nil
        ) {
            if eligibleServers.isEmpty {
                Text("No servers available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(eligibleServers, id: \.id) { server in
                    JinSettingsToggleRow(server.name, isOn: fixedMCPServerBinding(serverID: server.id))
                }
            }
        }
    }

    private var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func modelsForProvider(_ providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return []
        }
        return provider.selectableModels
    }

    private func ensureValidFixedModelSelection() {
        guard newChatModelMode == .fixed else { return }

        if providers.first(where: { $0.id == newChatFixedProviderID }) == nil {
            newChatFixedProviderID = providers.first(where: { $0.id == "openai" })?.id
                ?? providers.first?.id
                ?? "openai"
        }

        let models = modelsForProvider(newChatFixedProviderID)
        guard !models.isEmpty else { return }

        if !models.contains(where: { $0.id == newChatFixedModelID }) {
            newChatFixedModelID = models.first?.id ?? newChatFixedModelID
        }
    }

    private func fixedMCPServerBinding(serverID: String) -> Binding<Bool> {
        Binding(
            get: {
                let current = Set(AppPreferences.decodeStringArrayJSON(newChatFixedMCPServerIDsJSON))
                return current.contains(serverID)
            },
            set: { isOn in
                var current = Set(AppPreferences.decodeStringArrayJSON(newChatFixedMCPServerIDsJSON))
                if isOn {
                    current.insert(serverID)
                } else {
                    current.remove(serverID)
                }
                newChatFixedMCPServerIDsJSON = AppPreferences.encodeStringArrayJSON(Array(current).sorted())
            }
        )
    }
}
