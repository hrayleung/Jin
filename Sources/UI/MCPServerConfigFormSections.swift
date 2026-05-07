import SwiftUI
import SwiftData

struct MCPServerConfigurationErrorSection: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        JinSettingsSection("Configuration Error", style: .plain) {
            HStack {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .jinInlineErrorText()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MCPServerIdentitySection: View {
    @Bindable var server: MCPServerConfigEntity
    @Binding var transportKind: MCPTransportKind
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        JinSettingsSection("MCP Server") {
            JinSettingsPickerRow("Transport", selection: $transportKind) {
                Text("Command-line (stdio)").tag(MCPTransportKind.stdio)
                Text("Remote HTTP").tag(MCPTransportKind.http)
            }

            JinSettingsTextFieldRow("Name", fieldTitle: "Server name", text: $server.name)
                .onChange(of: server.name) { _, _ in try? modelContext.save() }

            JinSettingsControlRow("Icon") {
                MCPIconPickerField(
                    selectedIconID: Binding(
                        get: { server.iconID },
                        set: { newValue in
                            server.iconID = MCPServerFormSupport.normalizedIconID(newValue)
                            try? modelContext.save()
                        }
                    ),
                    defaultIconID: MCPIconCatalog.defaultIconID
                )
            }

            JinSettingsTextFieldRow(
                "ID",
                fieldTitle: "exa",
                supportingText: "Short identifier used inside Jin.",
                text: $server.id,
                usesMonospacedFont: true
            )
            .textSelection(.enabled)
            .onChange(of: server.id) { _, _ in try? modelContext.save() }

            JinSettingsToggleRow("Enabled", isOn: $server.isEnabled)
                .onChange(of: server.isEnabled) { _, _ in try? modelContext.save() }

            JinSettingsToggleRow("Auto-run Tools", isOn: $server.runToolsAutomatically)
                .onChange(of: server.runToolsAutomatically) { _, _ in try? modelContext.save() }
        }
    }
}

struct MCPServerStdioTransportSections: View {
    @Binding var command: String
    @Binding var argsText: String
    @Binding var envPairs: [EnvironmentVariablePair]
    let argsError: String?
    var showsNodeIsolationNote = false
    let showsFirecrawlAPIKeyWarning: Bool

    var body: some View {
        Group {
            JinSettingsSection("Stdio Transport") {
                JinSettingsTextFieldRow(
                    "Command",
                    fieldTitle: "npx",
                    text: $command,
                    usesMonospacedFont: true
                )
                .textSelection(.enabled)

                JinSettingsTextFieldRow(
                    "Arguments",
                    fieldTitle: "-y exa-mcp-server",
                    text: $argsText,
                    usesMonospacedFont: true
                )

                if showsNodeIsolationNote {
                    JinDetailsDisclosure(title: "Launcher Details") {
                        Text("For Node launchers (`npx`, `npm`, `pnpm`, `yarn`, `bunx`, `bun`), Jin isolates npm HOME/cache under Application Support.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("This avoids `~/.npmrc` permission and prefix conflicts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if showsFirecrawlAPIKeyWarning {
                    Text("Firecrawl MCP requires `FIRECRAWL_API_KEY` in Environment variables, otherwise initialize may never return.")
                        .jinInfoCallout()
                }

                if let argsError {
                    JinSettingsErrorText(text: argsError)
                }
            }

            JinSettingsSection("Environment Variables") {
                EnvironmentVariablesEditor(pairs: $envPairs)
            }
        }
    }
}

struct MCPServerHTTPTransportSections: View {
    @Binding var endpoint: String
    @Binding var httpStreaming: Bool
    let endpointError: String?
    @Binding var httpAuthKind: MCPHTTPAuthentication.FormKind
    @Binding var bearerToken: String
    @Binding var authHeaderName: String
    @Binding var authHeaderValue: String
    @Binding var headerPairs: [EnvironmentVariablePair]
    @Binding var isBearerTokenVisible: Bool
    @Binding var isHeaderValueVisible: Bool
    let authenticationError: String?

    var body: some View {
        Group {
            JinSettingsSection("HTTP Transport") {
                JinSettingsTextFieldRow(
                    "Endpoint URL",
                    fieldTitle: "https://mcp.exa.ai/mcp",
                    text: $endpoint,
                    usesMonospacedFont: true
                )
                .textSelection(.enabled)

                JinSettingsToggleRow("Enable streaming (SSE)", isOn: $httpStreaming)

                if let endpointError {
                    JinSettingsErrorText(text: endpointError)
                }
            }

            JinSettingsSection("Authentication") {
                JinSettingsPickerRow("Type", selection: $httpAuthKind) {
                    Text("None").tag(MCPHTTPAuthentication.FormKind.none)
                    Text("Bearer token").tag(MCPHTTPAuthentication.FormKind.bearerToken)
                    Text("Custom header").tag(MCPHTTPAuthentication.FormKind.customHeader)
                }

                switch httpAuthKind {
                case .none:
                    EmptyView()
                case .bearerToken:
                    JinSettingsSecureFieldRow(
                        "Bearer token",
                        text: $bearerToken,
                        isRevealed: $isBearerTokenVisible,
                        usesMonospacedFont: true,
                        revealHelp: "Show token",
                        concealHelp: "Hide token"
                    )
                case .customHeader:
                    JinSettingsTextFieldRow(
                        "Header name",
                        fieldTitle: "Authorization",
                        text: $authHeaderName,
                        usesMonospacedFont: true
                    )
                    JinSettingsSecureFieldRow(
                        "Header value",
                        text: $authHeaderValue,
                        isRevealed: $isHeaderValueVisible,
                        usesMonospacedFont: true
                    )
                }

                if let authenticationError {
                    JinSettingsErrorText(text: authenticationError)
                }
            }

            JinSettingsSection("Additional Headers") {
                EnvironmentVariablesEditor(pairs: $headerPairs)
            }
        }
    }
}
