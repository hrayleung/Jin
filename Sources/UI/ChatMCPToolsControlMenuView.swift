import SwiftUI

struct MCPServerMenuItem: Identifiable {
    let id: String
    let name: String
    let isOn: Binding<Bool>
}

struct MCPToolsControlMenuView: View {
    let isEnabled: Binding<Bool>
    let isMCPToolsEnabled: Bool
    let servers: [MCPServerMenuItem]
    let selectedServerIDs: Set<String>
    let usesCustomServerSelection: Bool
    let onUseAllServers: () -> Void

    var body: some View {
        Toggle("MCP Tools", isOn: isEnabled)

        if isMCPToolsEnabled {
            if servers.isEmpty {
                Divider()
                Text("No MCP servers enabled for automatic tool use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                Text("Servers")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(servers) { server in
                    Toggle(server.name, isOn: server.isOn)
                }

                if selectedServerIDs.isEmpty {
                    Divider()
                    Text("Select at least one server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if usesCustomServerSelection {
                    Divider()
                    Button("Use all servers", action: onUseAllServers)
                }
            }
        }
    }
}
