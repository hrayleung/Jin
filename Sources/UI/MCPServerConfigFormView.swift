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

    @State private var disabledTools: Set<String> = []

    @State private var verifying = false
    @State private var verifyError: String?
    @State private var tools: [MCPToolInfo] = []
    @State private var schemaPresentedTool: MCPToolInfo?

    @State private var loading = false

    var body: some View {
        Form {
            serverSection

            if transportKind == .stdio {
                stdioSections
            } else {
                httpSections
            }

            toolsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
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
            schemaSheet(for: tool)
        }
    }

    private var serverSection: some View {
        Section("Server") {
            Picker("Transport", selection: $transportKind) {
                Text("Command-line (stdio)").tag(MCPTransportKind.stdio)
                Text("Remote HTTP").tag(MCPTransportKind.http)
            }

            TextField("Name", text: $server.name)
                .onChange(of: server.name) { _, _ in try? modelContext.save() }
            MCPIconPickerField(
                selectedIconID: Binding(
                    get: { server.iconID },
                    set: { newValue in
                        let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let trimmed, !trimmed.isEmpty,
                           trimmed.caseInsensitiveCompare(MCPIconCatalog.defaultIconID) != .orderedSame {
                            server.iconID = trimmed
                        } else {
                            server.iconID = nil
                        }
                        try? modelContext.save()
                    }
                ),
                defaultIconID: MCPIconCatalog.defaultIconID
            )
            TextField("ID", text: $server.id)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .onChange(of: server.id) { _, _ in try? modelContext.save() }
                .help("Keep this short to avoid tool name length limits (e.g. \u{201C}exa\u{201D}).")

            Toggle("Enabled", isOn: $server.isEnabled)
                .onChange(of: server.isEnabled) { _, _ in try? modelContext.save() }
            Toggle("Run tools automatically", isOn: $server.runToolsAutomatically)
                .onChange(of: server.runToolsAutomatically) { _, _ in try? modelContext.save() }
        }
    }

    private var stdioSections: some View {
        Group {
            Section("Stdio transport") {
                TextField("Command", text: $command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                TextField("Arguments", text: $argsText)
                    .font(.system(.body, design: .monospaced))
                    .help("Space-separated. For complex quoting, prefer wrapping with a shell script.")

                if shouldShowNodeIsolationNote {
                    Text("For Node launchers (`npx`, `npm`, `pnpm`, `yarn`, `bunx`, `bun`), Jin isolates npm HOME/cache under Application Support to avoid ~/.npmrc permission/prefix issues.")
                        .jinInfoCallout()
                }

                if isFirecrawlMCP && !hasFirecrawlAPIKey {
                    Text("Firecrawl MCP requires `FIRECRAWL_API_KEY` in Environment variables, otherwise initialize may never return.")
                        .jinInfoCallout()
                }

                if let argsError {
                    Text(argsError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Environment variables") {
                EnvironmentVariablesEditor(pairs: $envPairs)
            }
        }
    }

    private var httpSections: some View {
        Group {
            Section("HTTP transport") {
                TextField("Endpoint", text: $endpoint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Toggle("Enable streaming (SSE)", isOn: $httpStreaming)

                if let endpointError {
                    Text(endpointError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Authentication") {
                Picker("Type", selection: $httpAuthKind) {
                    Text("None").tag(MCPHTTPAuthentication.FormKind.none)
                    Text("Bearer token").tag(MCPHTTPAuthentication.FormKind.bearerToken)
                    Text("Custom header").tag(MCPHTTPAuthentication.FormKind.customHeader)
                }

                switch httpAuthKind {
                case .none:
                    EmptyView()
                case .bearerToken:
                    SecureField("Bearer token", text: $bearerToken)
                        .font(.system(.body, design: .monospaced))
                case .customHeader:
                    TextField("Header name", text: $authHeaderName)
                        .font(.system(.body, design: .monospaced))
                    SecureField("Header value", text: $authHeaderValue)
                        .font(.system(.body, design: .monospaced))
                }

                if let authError = httpAuthenticationValidationError {
                    Text(authError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Additional headers") {
                EnvironmentVariablesEditor(pairs: $headerPairs)
            }
        }
    }

    private var toolsSection: some View {
        Section("Tools") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        verifyTools()
                    } label: {
                        HStack {
                            Text("Verify (View Tools)")
                            if verifying {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                    }
                    .disabled(verifying || hasTransportValidationError)

                    Spacer()

                    if !tools.isEmpty {
                        Button("Hide") {
                            tools = []
                            verifyError = nil
                        }
                        .disabled(verifying)
                    }
                }

                if let verifyError {
                    Text(verifyError)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .jinInlineErrorText()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !tools.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .topLeading)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(tools) { tool in
                            MCPToolCardView(
                                tool: tool,
                                isEnabled: Binding(
                                    get: { !disabledTools.contains(tool.name) },
                                    set: { isEnabled in
                                        if isEnabled {
                                            disabledTools.remove(tool.name)
                                        } else {
                                            disabledTools.insert(tool.name)
                                        }
                                        server.setDisabledTools(disabledTools)
                                        try? modelContext.save()
                                    }
                                ),
                                viewSchema: {
                                    schemaPresentedTool = tool
                                }
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: verifyError)
            .animation(.easeInOut(duration: 0.18), value: tools.count)
        }
    }

    private func schemaSheet(for tool: MCPToolInfo) -> some View {
        NavigationStack {
            ScrollView {
                if let schemaText = formattedSchemaText(tool.inputSchema) {
                    Text(schemaText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(JinSpacing.medium)
                        .jinSurface(.outlined, cornerRadius: JinRadius.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No schema available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(JinSpacing.medium)
                        .jinSurface(.outlined, cornerRadius: JinRadius.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(JinSemanticColor.detailSurface)
            .navigationTitle(tool.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { schemaPresentedTool = nil }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var hasTransportValidationError: Bool {
        switch transportKind {
        case .stdio:
            return command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || argsError != nil
        case .http:
            let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || endpointError != nil || httpAuthenticationValidationError != nil
        }
    }

    private func loadFromServer() {
        loading = true
        defer { loading = false }

        let transport = server.transportConfig()
        transportKind = transport.kind

        switch transport {
        case .stdio(let stdio):
            command = stdio.command
            argsText = CommandLineTokenizer.render(stdio.args)
            envPairs = stdio.env.keys.sorted().map { EnvironmentVariablePair(key: $0, value: stdio.env[$0] ?? "") }
            endpoint = ""
            applyHTTPAuthentication(.none)
            headerPairs = []
            httpStreaming = true
            endpointError = nil
        case .http(let http):
            endpoint = http.endpoint.absoluteString
            applyHTTPAuthentication(http.authentication)
            headerPairs = http.additionalHeaders.map { EnvironmentVariablePair(key: $0.name, value: $0.value) }
            httpStreaming = http.streaming
            command = ""
            argsText = ""
            envPairs = []
            argsError = nil
        }

        disabledTools = server.disabledTools()
        persistTransport()
    }

    private func persistTransport() {
        guard !loading else { return }

        switch transportKind {
        case .stdio:
            let parsedArgs: [String]
            do {
                parsedArgs = try CommandLineTokenizer.tokenize(argsText)
                argsError = nil
            } catch {
                argsError = error.localizedDescription
                return
            }

            let env: [String: String] = envPairs.reduce(into: [:]) { partial, pair in
                let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                partial[key] = pair.value
            }

            let transport = MCPTransportConfig.stdio(
                MCPStdioTransportConfig(
                    command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                    args: parsedArgs,
                    env: env
                )
            )
            server.setTransport(transport)
            endpointError = nil

        case .http:
            let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEndpoint.isEmpty, let endpointURL = URL(string: trimmedEndpoint), endpointURL.scheme != nil else {
                endpointError = "Invalid endpoint URL."
                return
            }
            guard let authentication = parsedHTTPAuthentication else {
                return
            }

            let headers: [MCPHeader] = headerPairs.compactMap { pair in
                let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return nil }
                return MCPHeader(name: key, value: pair.value, isSensitive: MCPHTTPTransportConfig.isSensitiveHeaderName(key))
            }

            let transport = MCPTransportConfig.http(
                MCPHTTPTransportConfig(
                    endpoint: endpointURL,
                    streaming: httpStreaming,
                    authentication: authentication,
                    additionalHeaders: headers
                )
            )
            server.setTransport(transport)
            argsError = nil
            endpointError = nil
        }

        server.lifecycleRaw = MCPLifecyclePolicy.persistent.rawValue
        server.isLongRunning = true
        try? modelContext.save()
    }

    private func verifyTools() {
        persistTransport()
        if hasTransportValidationError {
            verifyError = "Fix transport validation errors before verification."
            return
        }

        verifying = true
        verifyError = nil

        let config = server.toConfig()

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

    private func formattedSchemaText(_ schema: ParameterSchema) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(schema) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private var shouldShowNodeIsolationNote: Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCommand = (try? CommandLineTokenizer.tokenize(trimmed))?.first ?? trimmed
        let base = (parsedCommand as NSString).lastPathComponent.lowercased()
        return ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains(base)
    }

    private var isFirecrawlMCP: Bool {
        let cmd = command.lowercased()
        if cmd.contains("firecrawl-mcp") { return true }

        let args = (try? CommandLineTokenizer.tokenize(argsText)) ?? []
        return args.contains { $0.lowercased() == "firecrawl-mcp" }
    }

    private var hasFirecrawlAPIKey: Bool {
        envPairs.contains { pair in
            pair.key.trimmingCharacters(in: .whitespacesAndNewlines) == "FIRECRAWL_API_KEY"
                && !pair.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
}

private struct MCPToolCardView: View {
    let tool: MCPToolInfo
    @Binding var isEnabled: Bool
    let viewSchema: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text(tool.name)
                .font(.headline)

            if !tool.description.isEmpty {
                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            Button("… View Input Schema") {
                viewSchema()
            }
            .font(.caption)
            .buttonStyle(.link)

            Toggle("Enable", isOn: $isEnabled)
                .toggleStyle(.checkbox)
        }
        .padding(JinSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jinSurface(.outlined, cornerRadius: JinRadius.medium)
    }
}
