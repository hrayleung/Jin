import Foundation

enum SettingsSearchSupport {
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
