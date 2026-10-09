import SwiftUI

struct SettingsSidebarColumn: View {
    @Binding var selection: SettingsDestination?
    @Binding var searchText: String
    let providers: [ProviderConfigEntity]
    let servers: [MCPServerConfigEntity]
    let plugins: [SettingsView.PluginDescriptor]
    let onAddProvider: () -> Void
    let onAddServer: () -> Void
    let onDeleteProvider: (ProviderConfigEntity) -> Void
    let onDeleteServer: (MCPServerConfigEntity) -> Void
    let pluginEnabled: (String) -> Binding<Bool>

    @State private var providersExpanded = false
    @State private var serversExpanded = false
    @State private var pluginsExpanded = true

    private var isSearching: Bool { !SettingsSearchSupport.trimmedSearchText(searchText).isEmpty }
    private var categories: [GeneralSettingsCategory] {
        SettingsSearchSupport.filteredGeneralCategories(searchText: searchText)
    }

    var body: some View {
        List(selection: $selection) {
            if !categories.isEmpty {
                Section("General") {
                    ForEach(categories) { category in
                        Label(category.label, systemImage: category.systemImage)
                            .tag(SettingsDestination.general(category))
                    }
                }
            }

            if !isSearching || !providers.isEmpty {
                Section(isExpanded: expansion($providersExpanded)) {
                    ForEach(providers) { provider in
                        HStack(spacing: 8) {
                            ProviderIconView(
                                iconID: provider.resolvedProviderIconID, fallbackSystemName: "network", size: 16
                            )
                            .frame(width: 20)
                            Text(provider.name).lineLimit(1)
                                .foregroundStyle(provider.isEnabled ? .primary : .secondary)
                        }
                        .help(provider.name)
                        .tag(SettingsDestination.provider(provider.id))
                        .contextMenu {
                            Button("Delete Provider…", role: .destructive) { onDeleteProvider(provider) }
                        }
                    }
                    Button("Add Provider…", systemImage: "plus", action: onAddProvider)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Providers")
                }
            }

            if !isSearching || !servers.isEmpty {
                Section(isExpanded: expansion($serversExpanded)) {
                    ForEach(servers) { server in
                        HStack(spacing: 8) {
                            MCPIconView(iconID: server.resolvedMCPIconID, fallbackSystemName: "server.rack", size: 16)
                                .frame(width: 20)
                            Text(server.name).lineLimit(1)
                                .foregroundStyle(server.isEnabled ? .primary : .secondary)
                        }
                        .help(server.name)
                        .tag(SettingsDestination.server(server.id))
                        .contextMenu {
                            Button("Delete MCP Server…", role: .destructive) { onDeleteServer(server) }
                        }
                    }
                    Button("Add MCP Server…", systemImage: "plus", action: onAddServer)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("MCP Servers")
                }
            }

            if !plugins.isEmpty {
                Section(isExpanded: expansion($pluginsExpanded)) {
                    ForEach(plugins) { plugin in
                        Label(plugin.name, systemImage: plugin.systemImage)
                            .lineLimit(1)
                            .help(plugin.name)
                            .tag(SettingsDestination.plugin(plugin.id))
                            .contextMenu {
                                Toggle("Enabled", isOn: pluginEnabled(plugin.id))
                            }
                    }
                } header: {
                    Text("Plugins")
                }
            }
        }
        .listStyle(.sidebar)
        .labelStyle(SettingsNavigationLabelStyle())
        .listItemTint(.monochrome)
        .symbolRenderingMode(.monochrome)
        .symbolEffectsRemoved()
        .transaction(SettingsSidebarSymbolSupport.suppressAnimations)
        .onDeleteCommand {
            switch selection {
            case .provider(let id):
                if let provider = providers.first(where: { $0.id == id }) { onDeleteProvider(provider) }
            case .server(let id):
                if let server = servers.first(where: { $0.id == id }) { onDeleteServer(server) }
            case .general, .plugin, .none:
                break
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Menu {
                    Button("Add Provider…", action: onAddProvider)
                    Button("Add MCP Server…", action: onAddServer)
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a connection")
                .accessibilityLabel("Add a connection")
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .overlay {
            if isSearching && categories.isEmpty && providers.isEmpty && servers.isEmpty && plugins.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        .onAppear { revealSelection() }
        .onChange(of: selection) { _, _ in revealSelection() }
    }

    private func expansion(_ expanded: Binding<Bool>) -> Binding<Bool> {
        isSearching ? .constant(true) : expanded
    }

    private func revealSelection() {
        switch selection {
        case .provider: providersExpanded = true
        case .server: serversExpanded = true
        case .plugin: pluginsExpanded = true
        case .general, .none: break
        }
    }
}

private struct SettingsNavigationLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 13, weight: .regular))
                .frame(width: 20)
                .contentTransition(.identity)
            configuration.title
                .lineLimit(1)
        }
    }
}
