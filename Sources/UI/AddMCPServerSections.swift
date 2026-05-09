import SwiftUI

enum AddMCPServerPreset: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case exaHTTP = "Exa (Native HTTP)"
    case exaLocal = "Exa (Local via npx)"
    case firecrawlLocal = "Firecrawl (Local via npx)"

    var id: String { rawValue }
}

struct AddMCPServerQuickSetupSection: View {
    @Binding var preset: AddMCPServerPreset
    @Binding var isImportSectionExpanded: Bool
    @Binding var importJSON: String
    let importError: String?
    let onImport: () -> Void

    var body: some View {
        JinSettingsSection("Quick Setup") {
            JinSettingsPickerRow("Preset", selection: $preset) {
                ForEach(AddMCPServerPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }

            DisclosureGroup(isExpanded: $isImportSectionExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Import from JSON")
                            .font(.headline)

                        Spacer()

                        Button("Import", action: onImport)
                            .disabled(!AddMCPServerPresetSupport.canImportJSON(importJSON))
                    }

                    JinSettingsTextEditor(
                        text: $importJSON,
                        placeholder: "{ \"mcpServers\": { \"exa\": { \"type\": \"http\", \"url\": \"https://mcp.exa.ai/mcp\", \"headers\": { \"Authorization\": \"Bearer …\" } } } }",
                        minHeight: 120
                    )

                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .jinInlineErrorText()
                    } else {
                        JinDetailsDisclosure(title: "Import Details") {
                            Text("Accepts Claude Desktop `mcpServers` configs and single-server payloads. HTTP entries map to native HTTP transport.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.18), value: importError)
            } label: {
                Text("Import from JSON")
            }
        }
    }
}

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

struct AddMCPServerActionBar: View {
    let isAddDisabled: Bool
    let onCancel: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Add", action: onAdd)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isAddDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(JinSemanticColor.detailSurface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
