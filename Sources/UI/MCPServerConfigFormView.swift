import SwiftUI
import SwiftData

struct MCPServerConfigFormView: View {
    @Bindable var server: MCPServerConfigEntity
    @Environment(\.modelContext) private var modelContext

    @State private var transportKind: MCPTransportKind = .stdio

    @State private var command = ""
    @State private var argsText = ""
    @State private var argsError: String?
    @State private var envPairs: [EnvironmentVariablePair] = []

    @State private var endpoint = ""
    @State private var endpointError: String?
    @State private var httpAuthKind: MCPHTTPAuthentication.FormKind = .none
    @State private var bearerToken = ""
    @State private var authHeaderName = "Authorization"
    @State private var authHeaderValue = ""
    @State private var headerPairs: [EnvironmentVariablePair] = []
    @State private var httpStreaming = true

    @State private var isBearerTokenVisible = false
    @State private var isHeaderValueVisible = false

    @State private var disabledTools: Set<String> = []

    @State private var verifying = false
    @State private var verifyError: String?
    @State private var verifyErrorDetails: String?
    @State private var tools: [MCPToolInfo] = []
    @State private var schemaPresentedTool: MCPToolInfo?

    @State private var configError: String?
    @State private var loading = true
    @State private var lastPersistedTransport: MCPTransportConfig?

    var body: some View {
        JinSettingsPage(title: server.name, maxWidth: 720) {
            if let configError {
                Section {
                    Text(configError)
                        .jinInlineErrorText()
                }
            }

            JinSettingsSection("Server") {
                JinSettingsTextFieldRow("Name", text: $server.name)
                    .onChange(of: server.name) { _, _ in try? modelContext.save() }

                JinSettingsControlRow("Icon", controlAlignment: .leading) {
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

                JinSettingsToggleRow("Enabled", isOn: $server.isEnabled)
                    .onChange(of: server.isEnabled) { _, _ in try? modelContext.save() }

                JinSettingsToggleRow(
                    "Run tools automatically",
                    supportingText: "When off, Jin asks before each tool call.",
                    isOn: $server.runToolsAutomatically
                )
                .onChange(of: server.runToolsAutomatically) { _, _ in try? modelContext.save() }

                DisclosureGroup("Server ID") {
                    JinSettingsTextFieldRow(
                        "ID",
                        prompt: "exa",
                        supportingText: "Short identifier used inside Jin.",
                        text: $server.id,
                        usesMonospacedFont: true
                    )
                    .onChange(of: server.id) { _, _ in try? modelContext.save() }
                }
            }

            JinSettingsSection("Connection") {
                JinSettingsPickerRow("Transport", selection: $transportKind) {
                    Text("Local command").tag(MCPTransportKind.stdio)
                    Text("Remote HTTP").tag(MCPTransportKind.http)
                }

                if transportKind == .stdio {
                    JinSettingsTextFieldRow(
                        "Command",
                        prompt: "npx",
                        supportingText: MCPServerFormSupport.shouldShowNodeIsolationNote(command: command)
                            ? "Runs with an isolated home folder and cache, outside your project."
                            : nil,
                        text: $command,
                        usesMonospacedFont: true
                    )
                    JinSettingsTextFieldRow(
                        "Arguments",
                        prompt: "-y package-name",
                        text: $argsText,
                        usesMonospacedFont: true
                    )

                    MCPRemoteProxyHintView(command: command, argsText: argsText) { transport in
                        applyTransportDraft(MCPServerTransportDraftSupport.draft(from: .http(transport)))
                        persistTransport()
                    }

                    if let argsError {
                        JinSettingsErrorText(text: argsError)
                    }
                } else {
                    JinSettingsTextFieldRow(
                        "Endpoint URL",
                        prompt: "https://mcp.example.com/mcp",
                        text: $endpoint,
                        usesMonospacedFont: true
                    )
                    JinSettingsToggleRow(
                        "Streamable HTTP",
                        supportingText: "Turn off only if the server requires plain HTTP requests.",
                        isOn: $httpStreaming
                    )
                    if let endpointError {
                        JinSettingsErrorText(text: endpointError)
                    }
                }
            }

            if transportKind == .http {
                JinSettingsSection("Authentication") {
                    MCPHTTPAuthViews(
                        serverID: server.id,
                        endpoint: $endpoint,
                        httpAuthKind: $httpAuthKind,
                        bearerToken: $bearerToken,
                        authHeaderName: $authHeaderName,
                        authHeaderValue: $authHeaderValue,
                        isBearerTokenVisible: $isBearerTokenVisible,
                        isHeaderValueVisible: $isHeaderValueVisible,
                        authenticationError: httpAuthenticationValidationError,
                        compact: true
                    )
                }

                JinSettingsSection("Additional headers") {
                    EnvironmentVariablesEditor(pairs: $headerPairs, kind: .headers)
                }
            }

            if transportKind == .stdio {
                JinSettingsSection(
                    "Environment",
                    detail: "Passed to the local command when it starts."
                ) {
                    EnvironmentVariablesEditor(pairs: $envPairs)

                    if isFirecrawlMCP && !hasFirecrawlAPIKey {
                        Text("Add FIRECRAWL_API_KEY so Firecrawl can connect.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            JinSettingsSection(
                "Tools",
                detail: tools.isEmpty ? nil : "Only enabled tools are available to the model."
            ) {
                MCPServerToolsSection(
                    verifying: verifying,
                    hasTransportValidationError: hasTransportValidationError,
                    verifyError: verifyError,
                    verifyErrorDetails: verifyErrorDetails,
                    tools: tools,
                    isToolEnabled: { tool in
                        !disabledTools.contains(tool.name)
                    },
                    onVerify: verifyTools,
                    onHide: {
                        tools = []
                        verifyError = nil
                        verifyErrorDetails = nil
                    },
                    onSetToolEnabled: setToolEnabled,
                    onViewSchema: { tool in
                        schemaPresentedTool = tool
                    }
                )
            }
        }
        .disabled(loading)
        .task {
            hydrateFromServer()
            await Task.yield()
            loading = false
        }
        .onChange(of: transportKind) { _, _ in persistTransport() }
        .onChange(of: command) { _, _ in persistTransport() }
        .onChange(of: argsText) { _, _ in persistTransport() }
        .onChange(of: envPairs) { _, _ in persistTransport() }
        .onChange(of: endpoint) { _, _ in persistTransport() }
        .onChange(of: httpAuthKind) { _, _ in persistTransport() }
        .onChange(of: bearerToken) { _, _ in persistTransport() }
        .onChange(of: authHeaderName) { _, _ in persistTransport() }
        .onChange(of: authHeaderValue) { _, _ in persistTransport() }
        .onChange(of: headerPairs) { _, _ in persistTransport() }
        .onChange(of: httpStreaming) { _, _ in persistTransport() }
        .sheet(item: $schemaPresentedTool) { tool in
            MCPToolSchemaSheet(tool: tool) {
                schemaPresentedTool = nil
            }
        }
    }

    private var hasTransportValidationError: Bool {
        MCPServerFormSupport.hasTransportValidationError(
            transportKind: transportKind,
            command: command,
            argsError: argsError,
            endpoint: endpoint,
            endpointError: endpointError,
            httpAuthenticationValidationError: httpAuthenticationValidationError
        )
    }

    private func hydrateFromServer() {
        loading = true
        let persisted = server.transportConfig()
        lastPersistedTransport = persisted
        applyTransportDraft(MCPServerTransportDraftSupport.draft(from: persisted))

        do {
            disabledTools = try server.disabledTools()
        } catch {
            configError = "Failed to load disabled tools (defaulting to all enabled): \(error.localizedDescription)"
            disabledTools = []
        }
    }

    private func applyTransportDraft(_ draft: MCPServerTransportDraftSupport.Draft) {
        transportKind = draft.transportKind
        command = draft.command
        argsText = draft.argsText
        envPairs = draft.envPairs
        endpoint = draft.endpoint
        applyHTTPAuthentication(draft.httpAuthentication)
        headerPairs = draft.headerPairs
        httpStreaming = draft.httpStreaming
        argsError = nil
        endpointError = nil
    }

    private func persistTransport() {
        guard !loading else { return }

        let transport: MCPTransportConfig
        do {
            transport = try MCPServerTransportDraftSupport.buildTransport(from: transportBuildRequest)
        } catch let error as MCPServerTransportDraftSupport.BuildError {
            applyTransportBuildError(error)
            return
        } catch {
            configError = error.localizedDescription
            return
        }
        if transportKind == .stdio {
            argsError = nil
        }

        guard MCPServerFormSupport.shouldPersistTransport(
            draft: transport,
            lastPersisted: lastPersistedTransport
        ) else {
            return
        }

        do {
            try server.setTransport(transport)
        } catch {
            configError = "Failed to save transport config: \(error.localizedDescription)"
            return
        }
        clearTransportBuildError()

        server.lifecycleRaw = MCPLifecyclePolicy.persistent.rawValue
        server.isLongRunning = true
        do {
            try modelContext.save()
            lastPersistedTransport = transport
            configError = nil
        } catch {
            configError = "Failed to persist server settings: \(error.localizedDescription)"
        }
    }

    private var transportBuildRequest: MCPServerTransportDraftSupport.BuildRequest {
        MCPServerTransportDraftSupport.BuildRequest(
            transportKind: transportKind,
            command: command,
            argsText: argsText,
            envPairs: envPairs,
            endpoint: endpoint,
            httpAuthentication: parsedHTTPAuthentication,
            headerPairs: headerPairs,
            httpStreaming: httpStreaming
        )
    }

    private func applyTransportBuildError(_ error: MCPServerTransportDraftSupport.BuildError) {
        switch error {
        case .invalidArguments(let message):
            argsError = message
        case .invalidEndpointURL:
            endpointError = error.localizedDescription
        case .invalidAuthentication:
            break
        }
    }

    private func clearTransportBuildError() {
        argsError = nil
        endpointError = nil
    }

    private func verifyTools() {
        persistTransport()
        if configError != nil {
            verifyError = configError
            verifyErrorDetails = nil
            return
        }
        if hasTransportValidationError {
            verifyError = "Fix transport validation errors before verification."
            verifyErrorDetails = nil
            return
        }

        verifying = true
        verifyError = nil
        verifyErrorDetails = nil

        let config: MCPServerConfig
        do {
            config = try server.toConfig()
        } catch {
            verifyError = "Failed to load MCP server config: \(error.localizedDescription)"
            verifying = false
            return
        }

        Task {
            do {
                let tools = try await MCPHub.shared.listTools(for: config)
                await MainActor.run {
                    self.tools = tools
                    self.verifying = false
                }
            } catch {
                await MainActor.run {
                    let presentation = MCPErrorPresentation.make(from: error)
                    self.verifyError = presentation.summaryAndHint
                    self.verifyErrorDetails = presentation.details
                    self.verifying = false
                }
            }
        }
    }

    private var isFirecrawlMCP: Bool {
        MCPServerFormSupport.isFirecrawlMCP(command: command, argsText: argsText)
    }

    private var hasFirecrawlAPIKey: Bool {
        MCPServerFormSupport.hasFirecrawlAPIKey(in: envPairs)
    }

    private var httpAuthenticationValidationError: String? {
        MCPHTTPAuthentication.formValidationError(
            kind: httpAuthKind,
            bearerToken: bearerToken,
            headerName: authHeaderName,
            headerValue: authHeaderValue
        )
    }

    private var parsedHTTPAuthentication: MCPHTTPAuthentication? {
        MCPHTTPAuthentication.fromFormFields(
            kind: httpAuthKind,
            bearerToken: bearerToken,
            headerName: authHeaderName,
            headerValue: authHeaderValue
        )
    }

    private func applyHTTPAuthentication(_ authentication: MCPHTTPAuthentication) {
        let fields = authentication.formFields
        httpAuthKind = MCPHTTPAuthentication.FormKind.coerced(fields.kind, forEndpoint: endpoint)
        bearerToken = fields.bearerToken
        authHeaderName = fields.headerName
        authHeaderValue = fields.headerValue
        endpoint = MCPParallelSearchEndpoint.aligned(endpoint, to: httpAuthKind)
    }

    private func setToolEnabled(_ tool: MCPToolInfo, _ isEnabled: Bool) {
        let previous = disabledTools
        if isEnabled {
            disabledTools.remove(tool.name)
        } else {
            disabledTools.insert(tool.name)
        }
        do {
            try server.setDisabledTools(disabledTools)
            try modelContext.save()
        } catch {
            disabledTools = previous
            configError = "Failed to save tool settings: \(error.localizedDescription)"
        }
    }
}
