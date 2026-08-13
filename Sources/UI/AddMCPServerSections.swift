import SwiftUI

struct AddMCPServerIdentitySection: View {
    @Binding var id: String
    @Binding var name: String
    @Binding var iconID: String?
    @Binding var transportKind: MCPTransportKind
    @Binding var isEnabled: Bool
    @Binding var runToolsAutomatically: Bool

    var body: some View {
        JinSettingsSection("MCP Server") {
            JinSettingsTextFieldRow(
                "ID",
                fieldTitle: "exa",
                supportingText: "Short identifier (e.g. `git`).",
                text: $id,
                usesMonospacedFont: true
            )

            JinSettingsTextFieldRow("Name", fieldTitle: "Exa", text: $name)

            JinSettingsControlRow("Icon") {
                MCPIconPickerField(
                    selectedIconID: $iconID,
                    defaultIconID: MCPIconCatalog.defaultIconID
                )
            }

            JinSettingsPickerRow("Transport", selection: $transportKind) {
                Text("Command-line (stdio)").tag(MCPTransportKind.stdio)
                Text("Remote HTTP").tag(MCPTransportKind.http)
            }

            JinSettingsToggleRow("Enabled", isOn: $isEnabled)
            JinSettingsToggleRow("Run tools automatically", isOn: $runToolsAutomatically)
        }
    }
}
