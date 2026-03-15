import SwiftUI
import SwiftData

// MARK: - List Views

extension SettingsView {
    var providersList: some View {
        List(filteredProviders, selection: animatedSelectedProviderID) { provider in
            NavigationLink(value: provider.id) {
                HStack(spacing: JinSpacing.small + 2) {
                    ProviderIconView(iconID: provider.resolvedProviderIconID, fallbackSystemName: "network", size: 14)
                        .frame(width: 20, height: 20)
                        .jinSurface(.outlined, cornerRadius: JinRadius.small)
                        .opacity(provider.isEnabled ? 1 : 0.4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                        Text(ProviderType(rawValue: provider.typeRaw)?.displayName ?? provider.typeRaw)
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.secondary)
                    }
                    .opacity(provider.isEnabled ? 1 : 0.4)

                    Spacer()
                }
                .padding(.vertical, JinSpacing.xSmall)
            }
            .contextMenu {
                Button {
                    provider.isEnabled.toggle()
                    try? modelContext.save()
                } label: {
                    Label(
                        provider.isEnabled ? "Disable Provider" : "Enable Provider",
                        systemImage: provider.isEnabled ? "xmark.circle" : "checkmark.circle"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    requestDeleteProvider(provider)
                } label: {
                    Label("Delete Provider", systemImage: "trash")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
        .onDeleteCommand {
            requestDeleteSelectedProvider()
        }
        .overlay {
            if !trimmedSearchText.isEmpty, filteredProviders.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
    }

    var generalCategoriesList: some View {
        List(GeneralSettingsCategory.allCases, selection: animatedSelectedGeneralCategory) { category in
            NavigationLink(value: category) {
                HStack(spacing: JinSpacing.small + 2) {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .jinSurface(.outlined, cornerRadius: JinRadius.small)

                    Text(category.label)
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .padding(.vertical, JinSpacing.xSmall)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
    }

    var pluginsList: some View {
        List(filteredPlugins, selection: animatedSelectedPluginID) { plugin in
            let isSelected = selectedPluginID == plugin.id

            HStack(spacing: JinSpacing.small + 2) {
                Image(systemName: plugin.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .jinSurface(.outlined, cornerRadius: JinRadius.small)

                Text(plugin.name)
                    .font(.system(.body, design: .default))
                    .fontWeight(.medium)
                    .lineLimit(isSelected ? nil : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: isSelected)
                    .layoutPriority(1)
                    .animation(pluginSelectionAnimation, value: isSelected)

                Spacer(minLength: JinSpacing.small)

                Toggle("", isOn: pluginEnabledBinding(for: plugin.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .frame(width: 38, alignment: .trailing)
                    .help(isPluginEnabled(plugin.id) ? "Disable plugin" : "Enable plugin")
            }
            .padding(.vertical, JinSpacing.xSmall)
            .contentShape(Rectangle())
            .onTapGesture {
                guard selectedPluginID != plugin.id else { return }
                animatedSelectedPluginID.wrappedValue = plugin.id
            }
            .tag(plugin.id)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
        .overlay {
            if !trimmedSearchText.isEmpty, filteredPlugins.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
    }

    var providersListWithActions: some View {
        VStack(spacing: 0) {
            providersList

            Divider()

            settingsActionBar {
                Button {
                    showingAddProvider = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Add Provider")
                .accessibilityLabel("Add Provider")

                Spacer(minLength: JinSpacing.small)

                Button(role: .destructive) {
                    requestDeleteSelectedProvider()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(selectedProviderID == nil)
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }

    var mcpServersList: some View {
        List(filteredMCPServers, selection: animatedSelectedServerID) { server in
            NavigationLink(value: server.id) {
                HStack(spacing: JinSpacing.small + 2) {
                    ZStack(alignment: .bottomTrailing) {
                        MCPIconView(iconID: server.resolvedMCPIconID, fallbackSystemName: "server.rack", size: 14)
                            .frame(width: 20, height: 20)
                            .jinSurface(.subtle, cornerRadius: JinRadius.small)

                        Circle()
                            .fill(server.isEnabled ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .stroke(JinSemanticColor.panelSurface, lineWidth: 1)
                            )
                            .offset(x: 1, y: 1)
                    }
                    .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                        Text(server.transportSummary)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(server.transportKind == .http ? "HTTP" : "STDIO")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .jinSurface(.outlined, cornerRadius: JinRadius.small)
                }
                .padding(.vertical, JinSpacing.xSmall)
            }
            .contextMenu {
                Button(role: .destructive) {
                    requestDeleteServer(server)
                } label: {
                    Label("Delete Server", systemImage: "trash")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
        .onDeleteCommand {
            requestDeleteSelectedServer()
        }
        .overlay {
            if !trimmedSearchText.isEmpty, filteredMCPServers.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
    }

    var mcpServersListWithActions: some View {
        VStack(spacing: 0) {
            mcpServersList

            Divider()

            settingsActionBar {
                Button {
                    showingAddServer = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Add MCP Server")
                .accessibilityLabel("Add MCP Server")

                Spacer(minLength: JinSpacing.small)

                Button(role: .destructive) {
                    requestDeleteSelectedServer()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(selectedServerID == nil)
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }

    func settingsActionBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: JinSpacing.small) {
            content()
        }
        .padding(JinSpacing.medium)
        .background(JinSemanticColor.panelSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.45))
                .frame(height: JinStrokeWidth.hairline)
        }
    }
}
