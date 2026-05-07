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
    @State private var loading = false

    var body: some View {
        JinSettingsPage(maxWidth: 760) {
            if let configError {
                MCPServerConfigurationErrorSection(message: configError) {
                    self.configError = nil
                }
            }

            MCPServerIdentitySection(
                server: server,
                transportKind: $transportKind
            )

            if transportKind == .stdio {
                MCPServerStdioTransportSections(
                    command: $command,
                    argsText: $argsText,
                    envPairs: $envPairs,
                    argsError: argsError,
                    showsFirecrawlAPIKeyWarning: isFirecrawlMCP && !hasFirecrawlAPIKey
                )
            } else {
                MCPServerHTTPTransportSections(
                    endpoint: $endpoint,
                    httpStreaming: $httpStreaming,
                    endpointError: endpointError,
                    httpAuthKind: $httpAuthKind,
                    bearerToken: $bearerToken,
                    authHeaderName: $authHeaderName,
                    authHeaderValue: $authHeaderValue,
                    headerPairs: $headerPairs,
                    isBearerTokenVisible: $isBearerTokenVisible,
                    isHeaderValueVisible: $isHeaderValueVisible,
                    authenticationError: httpAuthenticationValidationError
                )
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
        .navigationTitle(server.name)
        .task {
            loadFromServer()
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

    private func loadFromServer() {
        loading = true
        defer { loading = false }

        applyTransportDraft(MCPServerTransportDraftSupport.draft(from: server.transportConfig()))

        do {
            disabledTools = try server.disabledTools()
        } catch {
            configError = "Failed to load disabled tools (defaulting to all enabled): \(error.localizedDescription)"
            disabledTools = []
        }
        persistTransport()
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

        do {
            try server.setTransport(transport)
            configError = nil
        } catch {
            configError = "Failed to save transport config: \(error.localizedDescription)"
            return
        }
        clearTransportBuildError()

        server.lifecycleRaw = MCPLifecyclePolicy.persistent.rawValue
        server.isLongRunning = true
        do {
            try modelContext.save()
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
        switch transportKind {
        case .stdio:
            argsError = nil
            endpointError = nil
        case .http:
            argsError = nil
            endpointError = nil
        }
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
        httpAuthKind = fields.kind
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
