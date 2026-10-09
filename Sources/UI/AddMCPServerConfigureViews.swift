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

            if !preset.isBlankCanvas {
                heroCard
            } else if preset == .custom {
                Text("Connect a local command or a remote HTTP server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }

            identityCard

            if preset.isBlankCanvas {
                transportCard
            }

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

            if preset.isBlankCanvas {
                JinSettingsCard {
                    additionalFields
                }
            }

            advancedCard
        }
        .jinSettingsLabelColumn()
    }

    private var heroCard: some View {
        JinSettingsCard(spacing: JinSpacing.medium, padding: JinSpacing.large) {
            HStack(alignment: .top, spacing: JinSpacing.medium) {
                heroIcon
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                        Text(heroTitle)
                            .font(.title3.weight(.semibold))

                        Spacer(minLength: 0)

                        if let badge = heroBadge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(JinSemanticColor.textSecondary)
                                .fixedSize()
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                JinSettingsSecureFieldRow(
                    title,
                    supportingText: help,
                    text: $credentialValue,
                    isRevealed: $isCredentialVisible,
                    usesMonospacedFont: true,
                    revealHelp: "Show \(title.lowercased())",
                    concealHelp: "Hide \(title.lowercased())"
                )
            case .pathArgument(let title, let help, let placeholder):
                JinSettingsTextFieldRow(
                    title,
                    prompt: placeholder,
                    supportingText: help,
                    text: $credentialValue,
                    usesMonospacedFont: true
                )
            }
        }
    }

    private var identityCard: some View {
        JinSettingsCard(spacing: JinSpacing.medium) {
            Text("Server")
                .font(.headline)

            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                JinSettingsTextFieldRow("Name", prompt: "Server name", text: $name)

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
                Text("Import configuration")
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
                Text("Paste a Claude Desktop configuration or a single server’s JSON.")
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: 6) {
                    Image(systemName: isAdvancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 8)

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
                        JinSettingsTextFieldRow(
                            "Server ID",
                            prompt: "exa",
                            supportingText: "Short identifier used inside Jin.",
                            text: $id,
                            usesMonospacedFont: true
                        )

                        JinSettingsControlRow("Icon", controlAlignment: .leading) {
                            MCPIconPickerField(
                                selectedIconID: $iconID,
                                defaultIconID: MCPIconCatalog.defaultIconID
                            )
                        }

                        if !preset.isBlankCanvas {
                            JinSettingsPickerRow("Transport", selection: $transportKind) {
                                Text("Local command").tag(MCPTransportKind.stdio)
                                Text("Remote HTTP").tag(MCPTransportKind.http)
                            }

                            if transportKind == .stdio {
                                stdioFields
                            } else {
                                httpFields
                            }

                            Divider()
                            additionalFields
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stdioFields: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            JinSettingsTextFieldRow(
                "Command",
                prompt: "npx",
                supportingText: MCPServerFormSupport.shouldShowNodeIsolationNote(command: command)
                    ? "Runs with an isolated home folder and cache, outside your project."
                    : nil,
                text: $command,
                usesMonospacedFont: true
            )
            labeledField("Arguments", prompt: "-y package-name", text: $args, monospaced: true)

            MCPRemoteProxyHintView(command: command, argsText: args) { transport in
                applyConvertedHTTP(transport)
            }
        }
    }

    @ViewBuilder
    private var httpFields: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            labeledField("Endpoint URL", prompt: "https://mcp.example.com/mcp", text: $endpoint, monospaced: true)
            JinSettingsToggleRow(
                "Streamable HTTP",
                supportingText: "Turn off only if the server requires plain HTTP requests.",
                isOn: $httpStreaming
            )
        }
    }

    private var additionalFields: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            Text(transportKind == .stdio ? "Environment" : "Additional headers")
                .font(.headline)
            if transportKind == .stdio {
                EnvironmentVariablesEditor(pairs: $envPairs)
                Text("Passed to the local command when it starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                EnvironmentVariablesEditor(pairs: $headerPairs, kind: .headers)
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
        JinSettingsTextFieldRow(title, prompt: prompt, text: text, usesMonospacedFont: monospaced)
    }
}
