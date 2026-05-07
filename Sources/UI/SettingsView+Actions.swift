import SwiftUI
import SwiftData

// MARK: - CRUD Actions & Selection

extension SettingsView {
    func refreshPluginStatus() async {
        let defaults = UserDefaults.standard
        let pluginEnabled = Dictionary(uniqueKeysWithValues: Self.availablePlugins.map { plugin in
            (plugin.id, AppPreferences.isPluginEnabled(plugin.id, defaults: defaults))
        })

        await MainActor.run {
            pluginEnabledByID = pluginEnabled
        }
    }

    func isPluginEnabled(_ pluginID: String) -> Bool {
        if let cached = pluginEnabledByID[pluginID] {
            return cached
        }
        return AppPreferences.isPluginEnabled(pluginID)
    }

    func pluginEnabledBinding(for pluginID: String) -> Binding<Bool> {
        Binding(
            get: { isPluginEnabled(pluginID) },
            set: { isEnabled in
                AppPreferences.setPluginEnabled(isEnabled, for: pluginID)
                pluginEnabledByID[pluginID] = isEnabled
                NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
            }
        )
    }

    func showOperationError(_ message: String) {
        operationErrorMessage = message
        showingOperationError = true
    }

    func providerDeletionMessage(_ provider: ProviderConfigEntity) -> String {
        let count = conversations.filter { $0.providerID == provider.id }.count
        return SettingsDeletionSupport.providerDeletionMessage(
            providerName: provider.name,
            chatCount: count
        )
    }

    func requestDeleteSelectedProvider() {
        guard let selectedProviderID,
              let provider = providers.first(where: { $0.id == selectedProviderID }) else {
            return
        }
        requestDeleteProvider(provider)
    }

    func requestDeleteProvider(_ provider: ProviderConfigEntity) {
        guard providers.count > 1 else {
            showOperationError("You must keep at least one provider configured.")
            return
        }

        providerPendingDeletion = provider
        showingDeleteProviderConfirmation = true
    }

    func deleteProvider(_ provider: ProviderConfigEntity) {
        Task { @MainActor in
            modelContext.delete(provider)
            try? modelContext.save()
            providerPendingDeletion = nil
        }
    }

    func requestDeleteSelectedServer() {
        guard let selectedServerID,
              let server = mcpServers.first(where: { $0.id == selectedServerID }) else {
            return
        }
        requestDeleteServer(server)
    }

    func requestDeleteServer(_ server: MCPServerConfigEntity) {
        serverPendingDeletion = server
        showingDeleteServerConfirmation = true
    }

    func deleteServer(_ server: MCPServerConfigEntity) {
        Task { @MainActor in
            modelContext.delete(server)
            try? modelContext.save()
            serverPendingDeletion = nil
        }
    }

    func ensureValidSelection() {
        let selection = SettingsSelectionSupport.validatedSelection(
            SettingsSelectionSupport.Selection(
                section: selectedSection,
                providerID: selectedProviderID,
                serverID: selectedServerID,
                pluginID: selectedPluginID,
                generalCategory: selectedGeneralCategory
            ),
            providerIDs: filteredProviders.map(\.id),
            serverIDs: filteredMCPServers.map(\.id),
            pluginIDs: filteredPlugins.map(\.id)
        )

        selectedSection = selection.section
        selectedProviderID = selection.providerID
        selectedServerID = selection.serverID
        selectedPluginID = selection.pluginID
        selectedGeneralCategory = selection.generalCategory
    }
}
