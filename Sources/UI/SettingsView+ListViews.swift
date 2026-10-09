import SwiftUI

enum SettingsDestination: Hashable {
    case general(GeneralSettingsCategory)
    case provider(String)
    case server(String)
    case plugin(String)
}

extension SettingsView {
    var navigationSelection: Binding<SettingsDestination?> {
        Binding(
            get: {
                switch selectedSection {
                case .general, .none: return .general(resolvedSelectedGeneralCategory ?? .appearance)
                case .providers: return resolvedSelectedProviderID.map(SettingsDestination.provider)
                case .mcpServers: return resolvedSelectedServerID.map(SettingsDestination.server)
                case .plugins: return resolvedSelectedPluginID.map(SettingsDestination.plugin)
                }
            },
            set: { destination in
                guard let destination else { return }
                switch destination {
                case .general(let category):
                    selectedSection = .general
                    selectedGeneralCategory = category
                case .provider(let id):
                    selectedSection = .providers
                    selectedProviderID = id
                case .server(let id):
                    selectedSection = .mcpServers
                    selectedServerID = id
                case .plugin(let id):
                    selectedSection = .plugins
                    selectedPluginID = id
                }
            }
        )
    }
}
