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
    @State private var tools: [MCPToolInfo] = []
    @State private var schemaPresentedTool: MCPToolInfo?

    @State private var configError: String?
    @State private var loading = true
    @State private var lastPersistedTransport: MCPTransportConfig?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    if let configError {
                        Text(configError)
                            .jinInlineErrorText()
                    }

                    heroCard
                    identityCard
                    connectionCard

                    if transportKind == .http {
                        JinSettingsCard {
                            MCPHTTPAuthViews(
                                serverID: server.id,
                                endpoint: endpoint,
                                httpAuthKind: $httpAuthKind,
                                bearerToken: $bearerToken,
                                authHeaderName: $authHeaderName,
                                authHeaderValue: $authHeaderValue,
                                isBearerTokenVisible: $isBearerTokenVisible,
                                isHeaderValueVisible: $isHeaderValueVisible,
                                authenticationError: httpAuthenticationValidationError
                            )
                        }
                    }

                    if transportKind == .stdio {
                        environmentCard
                    }

                    MCPServerToolsSection(
                        verifying: verifying,
                        hasTransportValidationError: hasTransportValidationError,
                        verifyError: verifyError,
                        tools: tools,
                        isToolEnabled: { tool in
                            !disabledTools.contains(tool.name)
                        },
                        onVerify: verifyTools,
                        onHide: {
                            tools = []
                            verifyError = nil
                        },
                        onSetToolEnabled: setToolEnabled,
                        onViewSchema: { tool in
                            schemaPresentedTool = tool
                        }
                    )
                }
                .frame(maxWidth: 720, alignment: .leading)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(JinSpacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JinSemanticColor.detailSurface)
        .disabled(loading)
        .toolbar(.hidden, for: .automatic)
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

    private var heroCard: some View {
        JinSettingsCard(spacing: JinSpacing.medium, padding: JinSpacing.large) {
            HStack(alignment: .top, spacing: JinSpacing.medium) {
                MCPIconView(iconID: server.resolvedMCPIconID, size: 30)
                    .frame(width: 48, height: 48)
                    .jinSurface(.subtle, cornerRadius: JinRadius.medium)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                        Text(server.name)
                            .font(.title3.weight(.semibold))
                        Spacer(minLength: 0)
                        Text(transportKind == .http ? "HTTP" : "Local")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(JinSemanticColor.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .jinSurface(.outlined, cornerRadius: JinRadius.small)
                    }

                    Text(server.transportSummary)
                        .font(.caption)
                        .foregroundStyle(JinSemanticColor.textSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var identityCard: some View {
        JinSettingsCard {
            Text("Server")
                .font(.headline)

            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                labeled("Name") {
                    JinSettingsTextField(text: $server.name)
                        .onChange(of: server.name) { _, _ in try? modelContext.save() }
                }

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

                JinSettingsToggleRow("Enabled", isOn: $server.isEnabled)
                    .onChange(of: server.isEnabled) { _, _ in try? modelContext.save() }

                JinSettingsToggleRow(
                    "Run tools automatically",
                    supportingText: "When off, Jin asks before each tool call.",
                    isOn: $server.runToolsAutomatically
                )
                .onChange(of: server.runToolsAutomatically) { _, _ in try? modelContext.save() }

                JinDetailsDisclosure(title: "Server ID") {
                    labeled("ID") {
                        JinSettingsTextField("exa", text: $server.id, usesMonospacedFont: true)
                            .onChange(of: server.id) { _, _ in try? modelContext.save() }
                        Text("Short identifier used inside Jin.")
                            .font(.caption)
                            .foregroundStyle(JinSemanticColor.textSecondary)
                    }
                }
            }
        }
    }

    private var connectionCard: some View {
        JinSettingsCard {
            Text("Connection")
                .font(.headline)

            VStack(alignment: .leading, spacing: JinSpacing.medium) {
                JinSettingsPickerRow("Transport", selection: $transportKind) {
                    Text("Local command").tag(MCPTransportKind.stdio)
                    Text("Remote HTTP").tag(MCPTransportKind.http)
                }

                if transportKind == .stdio {
                    labeled("Command") {
                        JinSettingsTextField("npx", text: $command, usesMonospacedFont: true)
                    }
                    labeled("Arguments") {
                        JinSettingsTextField("-y package-name", text: $argsText, usesMonospacedFont: true)
                    }

                    if MCPServerFormSupport.shouldShowNodeIsolationNote(command: command) {
                        Text("Node launchers run with an isolated HOME/cache to avoid ~/.npmrc conflicts.")
                            .font(.caption)
                            .foregroundStyle(JinSemanticColor.textSecondary)
                    }

                    if isFirecrawlMCP && !hasFirecrawlAPIKey {
                        Text("Firecrawl needs FIRECRAWL_API_KEY in Environment, or initialize may never return.")
                            .jinInfoCallout()
                    }

                    if let argsError {
                        JinSettingsErrorText(text: argsError)
                    }
                } else {
                    labeled("Endpoint URL") {
                        JinSettingsTextField("https://mcp.example.com/mcp", text: $endpoint, usesMonospacedFont: true)
                    }
                    JinSettingsToggleRow(
                        "Streamable HTTP",
                        supportingText: "Leave on unless this server only accepts plain request/response HTTP.",
                        isOn: $httpStreaming
                    )
                    if let endpointError {
                        JinSettingsErrorText(text: endpointError)
                    }

                    labeled("Additional headers") {
                        EnvironmentVariablesEditor(pairs: $headerPairs)
                    }
                }
            }
        }
    }

    private var environmentCard: some View {
        JinSettingsCard {
            Text("Environment")
                .font(.headline)
            EnvironmentVariablesEditor(pairs: $envPairs)
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            Text(title)
                .font(.subheadline.weight(.medium))
            content()
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
            return
        }
        if hasTransportValidationError {
            verifyError = "Fix transport validation errors before verification."
            return
        }

        verifying = true
        verifyError = nil

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
                    self.verifyError = error.localizedDescription
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
