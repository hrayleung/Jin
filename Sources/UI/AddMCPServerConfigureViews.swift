import SwiftUI

struct AddMCPServerConfigureSection: View {
    let preset: AddMCPServerPreset
    let catalogItem: MCPServerCatalogItem?

    @Binding var id: String
    @Binding var name: String
    @Binding var iconID: String?
    @Binding var transportKind: MCPTransportKind
    @Binding var isEnabled: Bool
    @Binding var runToolsAutomatically: Bool
    @Binding var credentialValue: String
    @Binding var isCredentialVisible: Bool

    @Binding var command: String
    @Binding var args: String
    @Binding var envPairs: [EnvironmentVariablePair]
    @Binding var endpoint: String
    @Binding var httpAuthKind: MCPHTTPAuthentication.FormKind
    @Binding var bearerToken: String
    @Binding var authHeaderName: String
    @Binding var authHeaderValue: String
    @Binding var headerPairs: [EnvironmentVariablePair]
    @Binding var httpStreaming: Bool
    @Binding var isBearerTokenVisible: Bool
    @Binding var isHeaderValueVisible: Bool
    @Binding var importJSON: String

    let importError: String?
    let authenticationError: String?
    let onImport: () -> Void

    @State private var isAdvancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            if let importError, preset != .importJSON {
                Text(importError)
                    .jinInlineErrorText()
            }

            if preset == .importJSON {
                importCard
            }

            heroCard

            if transportKind == .http {
                JinSettingsCard {
                    MCPHTTPAuthViews(
                        serverID: id.isEmpty ? (catalogItem?.preset.rawValue ?? "draft") : id,
                        endpoint: $endpoint,
                        httpAuthKind: $httpAuthKind,
                        bearerToken: $bearerToken,
                        authHeaderName: $authHeaderName,
                        authHeaderValue: $authHeaderValue,
                        isBearerTokenVisible: $isBearerTokenVisible,
                        isHeaderValueVisible: $isHeaderValueVisible,
                        authenticationError: authenticationError
                    )
                }
            } else if let catalogItem, let credential = catalogItem.credential {
                credentialCard(credential)
            }

            identityCard

            if preset == .custom {
                transportCard
            }

            advancedCard
        }
    }

    private var heroCard: some View {
        JinSettingsCard(spacing: JinSpacing.medium, padding: JinSpacing.large) {
            HStack(alignment: .top, spacing: JinSpacing.medium) {
                heroIcon
                    .frame(width: 48, height: 48)
                    .jinSurface(.subtle, cornerRadius: JinRadius.medium)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                        Text(heroTitle)
                            .font(.title3.weight(.semibold))

                        Spacer(minLength: 0)

                        if let badge = heroBadge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(JinSemanticColor.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .jinSurface(.outlined, cornerRadius: JinRadius.small)
                        }
                    }

                    Text(heroSummary)
                        .font(.callout)
                        .foregroundStyle(JinSemanticColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let docsURL = catalogItem?.docsURL {
                        Link("Setup guide", destination: docsURL)
                            .font(.caption.weight(.semibold))
                            .padding(.top, 2)
                    }
                }
            }

            if let note = catalogItem?.note {
                Text(note)
                    .jinInfoCallout()
            }
        }
    }

    @ViewBuilder
    private var heroIcon: some View {
        if let catalogItem {
            AddMCPServerCatalogIcon(item: catalogItem, size: 30)
        } else if preset == .importJSON {
            Image(systemName: "square.and.arrow.down")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            MCPIconView(iconID: iconID ?? MCPIconCatalog.defaultIconID, size: 30)
        }
    }

    private var heroTitle: String {
        catalogItem?.title ?? (preset == .importJSON ? "Import JSON" : "Custom server")
    }

    private var heroSummary: String {
        if let catalogItem {
            return catalogItem.summary
        }
        if preset == .importJSON {
            return "Paste a Claude Desktop mcpServers config or a single-server payload."
        }
        return "Connect any local command or remote HTTP MCP server."
    }

    private var heroBadge: String? {
        if let catalogItem {
            return catalogItem.transportBadge
        }
        return preset == .importJSON ? "JSON" : nil
    }

    private func credentialCard(_ credential: MCPServerCatalogCredential) -> some View {
        JinSettingsCard(spacing: JinSpacing.medium) {
            Text("Connect")
                .font(.headline)

            switch credential {
            case .oauth(let help):
                Text(help)
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textSecondary)
            case .bearerToken(let title, let help),
                 .header(_, let title, let help),
                 .environment(_, let title, let help):
                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    JinRevealableSecureField(
                        prompt: "",
                        text: $credentialValue,
                        isRevealed: $isCredentialVisible,
                        usesMonospacedFont: true,
                        revealHelp: "Show \(title.lowercased())",
                        concealHelp: "Hide \(title.lowercased())"
                    )
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(JinSemanticColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .pathArgument(let title, let help, let placeholder):
                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    JinSettingsTextField(placeholder, text: $credentialValue, usesMonospacedFont: true)
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(JinSemanticColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var identityCard: some View {
        JinSettingsCard(spacing: JinSpacing.medium) {
            Text("Server")
                .font(.headline)

            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                    JinSettingsTextField(text: $name)
                }

                JinSettingsToggleRow("Enabled", isOn: $isEnabled)
                JinSettingsToggleRow(
                    "Run tools automatically",
                    supportingText: "When off, Jin asks before each tool call.",
                    isOn: $runToolsAutomatically
                )
            }
        }
    }

    private var transportCard: some View {
        JinSettingsCard(spacing: JinSpacing.medium) {
            Text("Connection")
                .font(.headline)

            JinSettingsPickerRow("Transport", selection: $transportKind) {
                Text("Local command").tag(MCPTransportKind.stdio)
                Text("Remote HTTP").tag(MCPTransportKind.http)
            }

            if transportKind == .stdio {
                stdioFields
            } else {
                httpFields
            }
        }
    }

    private var importCard: some View {
        JinSettingsCard(spacing: JinSpacing.medium) {
            HStack {
                Text("JSON")
                    .font(.headline)
                Spacer()
                Button("Import", action: onImport)
                    .disabled(!AddMCPServerPresetSupport.canImportJSON(importJSON))
            }

            JinSettingsTextEditor(
                text: $importJSON,
                placeholder: "{ \"mcpServers\": { \"exa\": { \"type\": \"http\", \"url\": \"https://mcp.exa.ai/mcp\" } } }",
                minHeight: 140
            )

            if let importError {
                Text(importError)
                    .jinInlineErrorText()
            } else {
                Text("Accepts Claude Desktop mcpServers configs and single-server payloads. HTTP entries map to native HTTP transport.")
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textSecondary)
            }
        }
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isAdvancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: JinSpacing.small) {
                    Image(systemName: isAdvancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text("Advanced")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isAdvancedExpanded ? "Expanded" : "Collapsed")

            if isAdvancedExpanded {
                JinSettingsCard(spacing: JinSpacing.medium) {
                    VStack(alignment: .leading, spacing: JinSpacing.medium) {
                        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                            Text("ID")
                                .font(.subheadline.weight(.medium))
                            JinSettingsTextField("exa", text: $id, usesMonospacedFont: true)
                            Text("Short identifier used inside Jin.")
                                .font(.caption)
                                .foregroundStyle(JinSemanticColor.textSecondary)
                        }

                        JinSettingsControlRow("Icon") {
                            MCPIconPickerField(
                                selectedIconID: $iconID,
                                defaultIconID: MCPIconCatalog.defaultIconID
                            )
                        }

                        if preset != .custom {
                            JinSettingsPickerRow("Transport", selection: $transportKind) {
                                Text("Local command").tag(MCPTransportKind.stdio)
                                Text("Remote HTTP").tag(MCPTransportKind.http)
                            }

                            if transportKind == .stdio {
                                stdioFields
                            } else {
                                httpFields
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stdioFields: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            labeledField("Command", prompt: "npx", text: $command, monospaced: true)
            labeledField("Arguments", prompt: "-y package-name", text: $args, monospaced: true)

            if MCPServerFormSupport.shouldShowNodeIsolationNote(command: command) {
                Text("Node launchers run with an isolated HOME/cache, and start in a temporary folder so ~/.npmrc is not treated as a project config.")
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textSecondary)
            }

            MCPRemoteProxyHintView(command: command, argsText: args) { transport in
                applyConvertedHTTP(transport)
            }

            EnvironmentVariablesEditor(pairs: $envPairs)
        }
    }

    @ViewBuilder
    private var httpFields: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            labeledField("Endpoint URL", prompt: "https://mcp.example.com/mcp", text: $endpoint, monospaced: true)
            JinSettingsToggleRow(
                "Streamable HTTP",
                supportingText: "Leave on unless this server only accepts plain request/response HTTP.",
                isOn: $httpStreaming
            )

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Additional headers")
                    .font(.subheadline.weight(.medium))
                EnvironmentVariablesEditor(pairs: $headerPairs)
            }
        }
    }

    private func applyConvertedHTTP(_ transport: MCPHTTPTransportConfig) {
        let draft = MCPServerTransportDraftSupport.draft(from: .http(transport))
        transportKind = draft.transportKind
        command = draft.command
        args = draft.argsText
        envPairs = draft.envPairs
        endpoint = draft.endpoint
        headerPairs = draft.headerPairs
        httpStreaming = draft.httpStreaming
        let fields = draft.httpAuthentication.formFields
        httpAuthKind = MCPHTTPAuthentication.FormKind.coerced(fields.kind, forEndpoint: draft.endpoint)
        bearerToken = fields.bearerToken
        authHeaderName = fields.headerName
        authHeaderValue = fields.headerValue
        endpoint = MCPParallelSearchEndpoint.aligned(endpoint, to: httpAuthKind)
    }

    private func labeledField(
        _ title: String,
        prompt: String,
        text: Binding<String>,
        monospaced: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.medium))
            JinSettingsTextField(prompt, text: text, usesMonospacedFont: monospaced)
        }
    }
}
