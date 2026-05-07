import Foundation

enum SettingsSelectionSupport {
    struct Selection: Equatable {
        var section: SettingsView.SettingsSection?
        var providerID: String?
        var serverID: String?
        var pluginID: String?
        var generalCategory: GeneralSettingsCategory?
    }

    static func validatedSelection(
        _ selection: Selection,
        providerIDs: [String],
        serverIDs: [String],
        pluginIDs: [String],
        defaultGeneralCategory: GeneralSettingsCategory = .appearance
    ) -> Selection {
        let section = selection.section ?? .providers

        switch section {
        case .providers:
            return Selection(
                section: .providers,
                providerID: validatedID(selection.providerID, in: providerIDs)
            )
        case .mcpServers:
            return Selection(
                section: .mcpServers,
                serverID: validatedID(selection.serverID, in: serverIDs)
            )
        case .plugins:
            return Selection(
                section: .plugins,
                pluginID: validatedID(selection.pluginID, in: pluginIDs)
            )
        case .general:
            return Selection(
                section: .general,
                generalCategory: selection.generalCategory ?? defaultGeneralCategory
            )
        }
    }

    private static func validatedID(_ selectedID: String?, in ids: [String]) -> String? {
        if let selectedID, ids.contains(selectedID) {
            return selectedID
        }
        return ids.first
    }
}
