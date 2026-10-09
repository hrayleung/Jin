import Foundation

enum SettingsSearchSupport {
    static func filteredGeneralCategories(searchText: String) -> [GeneralSettingsCategory] {
        filteredValues(GeneralSettingsCategory.allCases, searchText: searchText) { category, query in
            matches(query, in: [category.label, category.subtitle, keywords(for: category)])
        }
    }

    private static func keywords(for category: GeneralSettingsCategory) -> String {
        switch category {
        case .appearance:
            return "light dark system font typography scrollbars minimap thinking code blocks line numbers"
        case .chat: return "return enter send notifications diagnostics logs network trace"
        case .shortcuts: return "keyboard keys command hotkey hints restore"
        case .defaults: return "new chat model provider MCP tools servers"
        case .updates: return "version build automatic beta release"
        case .data: return "storage database cache attachments import export backup recovery delete"
        }
    }

    static func trimmedSearchText(_ searchText: String) -> String {
        searchText.trimmedNonEmpty ?? ""
    }

    static func filteredProviders(
        _ providers: [ProviderConfigEntity],
        searchText: String
    ) -> [ProviderConfigEntity] {
        filteredValues(providers, searchText: searchText) { provider, query in
            let typeName = ProviderType(rawValue: provider.typeRaw)?.displayName ?? provider.typeRaw
            return matches(query, in: [
                provider.name,
                provider.typeRaw,
                typeName,
                provider.baseURL ?? ""
            ])
        }
    }

    static func filteredMCPServers(
        _ servers: [MCPServerConfigEntity],
        searchText: String
    ) -> [MCPServerConfigEntity] {
        filteredValues(servers, searchText: searchText) { server, query in
            matches(query, in: [
                server.name,
                server.id,
                server.transportSummary,
                server.transportKind.rawValue
            ])
        }
    }

    static func filteredPlugins(
        _ plugins: [SettingsView.PluginDescriptor],
        searchText: String
    ) -> [SettingsView.PluginDescriptor] {
        filteredValues(plugins, searchText: searchText) { plugin, query in
            matches(query, in: [plugin.name, plugin.summary])
        }
    }

    private static func filteredValues<Value>(
        _ values: [Value],
        searchText: String,
        matches: (Value, String) -> Bool
    ) -> [Value] {
        let query = trimmedSearchText(searchText)
        guard !query.isEmpty else { return values }

        return values.filter { matches($0, query) }
    }

    private static func matches(_ query: String, in fields: [String]) -> Bool {
        fields.contains { field in
            field.localizedCaseInsensitiveContains(query)
        }
    }
}
