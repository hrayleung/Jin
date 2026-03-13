import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AddMCPServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Preset: String, CaseIterable, Identifiable {
        case custom = "Custom"
        case exaHTTP = "Exa (Native HTTP)"
        case exaLocal = "Exa (Local via npx)"
        case firecrawlLocal = "Firecrawl (Local via npx)"

        var id: String { rawValue }
    }

    @State private var id = ""
    @State private var name = ""
    @State private var iconID: String?
    @State private var transportKind: MCPTransportKind = .stdio

    @State private var command = ""
    @State private var args = ""
    @State private var envPairs: [EnvironmentVariablePair] = []

    @State private var endpoint = ""
    @State private var httpAuthKind: MCPHTTPAuthentication.FormKind = .none
    @State private var bearerToken = ""
    @State private var authHeaderName = "Authorization"
    @State private var authHeaderValue = ""
    @State private var headerPairs: [EnvironmentVariablePair] = []
    @State private var httpStreaming = true
    @State private var isBearerTokenVisible = false
    @State private var isHeaderValueVisible = false

    @State private var runToolsAutomatically = true
    @State private var isEnabled = true

    @State private var preset: Preset = .custom
    @State private var isImportSectionExpanded = false
    @State private var importJSON = ""
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick setup") {
                    Picker("Preset", selection: $preset) {
                        ForEach(Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .onChange(of: preset) { _, newValue in
                        applyPreset(newValue)
                    }

                    DisclosureGroup(isExpanded: $isImportSectionExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Import from JSON")
                                    .font(.headline)
                                Spacer()
                                Button("Import") { importFromJSON() }
                                    .disabled(importJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            TextEditor(text: $importJSON)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 120)
                                .jinTextEditorField(cornerRadius: JinRadius.small)
                                .overlay(alignment: .topLeading) {
                                    if importJSON.isEmpty {
                                        Text("{ \"mcpServers\": { \"exa\": { \"type\": \"http\", \"url\": \"https://mcp.exa.ai/mcp\", \"headers\": { \"Authorization\": \"Bearer …\" } } } }")
                                            .foregroundColor(.secondary)
                                            .padding(.top, 8)
                                            .padding(.leading, 5)
                                            .allowsHitTesting(false)
                                    }
                                }

                            if let importError {
                                Text(importError)
                                    .font(.caption)
                                    .jinInlineErrorText()
                            } else {
                                Text("Supports Claude Desktop-style configs (`mcpServers`) plus single-server payloads. HTTP imports are mapped to native HTTP transport.")
                                    .jinInfoCallout()
                            }
                        }
                        .padding(.top, 4)
                        .animation(.easeInOut(duration: 0.18), value: importError)
                    } label: {
                        Text("Import from JSON")
                    }
                }

                Section("Server") {
                    TextField("ID", text: $id)
                        .help("Short identifier (e.g. 'git').")
                    TextField("Name", text: $name)
                    MCPIconPickerField(
                        selectedIconID: $iconID,
                        defaultIconID: MCPIconCatalog.defaultIconID
                    )

                    Picker("Transport", selection: $transportKind) {
                        Text("Command-line (stdio)").tag(MCPTransportKind.stdio)
                        Text("Remote HTTP").tag(MCPTransportKind.http)
                    }

                    Toggle("Enabled", isOn: $isEnabled)
                    Toggle("Run tools automatically", isOn: $runToolsAutomatically)
                }

                if transportKind == .stdio {
                    Section("Stdio transport") {
                        TextField("Command", text: $command)
                            .font(.system(.body, design: .monospaced))
                        TextField("Arguments", text: $args)
                            .font(.system(.body, design: .monospaced))

                        if shouldShowNodeIsolationNote {
                            Text("For Node launchers (`npx`, `npm`, `pnpm`, `yarn`, `bunx`, `bun`), Jin isolates npm HOME/cache under Application Support to avoid ~/.npmrc permission or prefix conflicts.")
                                .jinInfoCallout()
                        }
                    }

                    Section("Environment variables") {
                        EnvironmentVariablesEditor(pairs: $envPairs)
                    }
                } else {
                    Section("HTTP transport") {
                        TextField("Endpoint", text: $endpoint)
                            .font(.system(.body, design: .monospaced))

                        Toggle("Enable streaming (SSE)", isOn: $httpStreaming)
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
                            HStack(spacing: 8) {
                                Group {
                                    if isBearerTokenVisible {
                                        TextField("Bearer token", text: $bearerToken)
                                            .font(.system(.body, design: .monospaced))
                                    } else {
                                        SecureField("Bearer token", text: $bearerToken)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                }
                                Button {
                                    isBearerTokenVisible.toggle()
                                } label: {
                                    Image(systemName: isBearerTokenVisible ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .help(isBearerTokenVisible ? "Hide token" : "Show token")
                                .disabled(bearerToken.isEmpty)
                            }
                        case .customHeader:
                            TextField("Header name", text: $authHeaderName)
                                .font(.system(.body, design: .monospaced))
                            HStack(spacing: 8) {
                                Group {
                                    if isHeaderValueVisible {
                                        TextField("Header value", text: $authHeaderValue)
                                            .font(.system(.body, design: .monospaced))
                                    } else {
                                        SecureField("Header value", text: $authHeaderValue)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                }
                                Button {
                                    isHeaderValueVisible.toggle()
                                } label: {
                                    Image(systemName: isHeaderValueVisible ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .help(isHeaderValueVisible ? "Hide value" : "Show value")
                                .disabled(authHeaderValue.isEmpty)
                            }
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
            .safeAreaInset(edge: .top, spacing: 0) {
                addMCPServerActionBar
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Add MCP Server")
            .onExitCommand { dismiss() }
            .frame(
                minWidth: 620,
                idealWidth: 680,
                maxWidth: 760,
                minHeight: 540,
                idealHeight: 680,
                maxHeight: 760
            )
        }
        #if os(macOS)
        .background(MovableWindowHelper())
        #endif
    }

    private var addMCPServerActionBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Add") { addServer() }
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

    private var isAddDisabled: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return true }

        switch transportKind {
        case .stdio:
            return command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .http:
            return parsedEndpoint == nil || parsedHTTPAuthentication == nil
        }
    }

    private var parsedEndpoint: URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else {
            return nil
        }
        return url
    }

    private var shouldShowNodeIsolationNote: Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCommand = (try? CommandLineTokenizer.tokenize(trimmed))?.first ?? trimmed
        let base = (parsedCommand as NSString).lastPathComponent.lowercased()
        return ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains(base)
    }

    private func applyPreset(_ preset: Preset) {
        importError = nil

        switch preset {
        case .custom:
            break
        case .exaHTTP:
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { id = "exa" }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "Exa" }
            transportKind = .http
            endpoint = "https://mcp.exa.ai/mcp"
            applyHTTPAuthentication(.none)
            if !headerPairs.contains(where: { $0.key.caseInsensitiveCompare("X-Client") == .orderedSame }) {
                headerPairs.append(EnvironmentVariablePair(key: "X-Client", value: "jin"))
            }
        case .exaLocal:
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { id = "exa" }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "Exa" }
            transportKind = .stdio
            command = "npx"
            args = "-y exa-mcp-server"
            if envPairs.first(where: { $0.key == "EXA_API_KEY" }) == nil {
                envPairs.append(EnvironmentVariablePair(key: "EXA_API_KEY", value: ""))
            }
        case .firecrawlLocal:
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { id = "firecrawl" }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "Firecrawl" }
            transportKind = .stdio
            command = "npx"
            args = "-y firecrawl-mcp"
            if envPairs.first(where: { $0.key == "FIRECRAWL_API_KEY" }) == nil {
                envPairs.append(EnvironmentVariablePair(key: "FIRECRAWL_API_KEY", value: ""))
            }
        }
    }

    private func importFromJSON() {
        importError = nil

        do {
            let imported = try MCPServerImportParser.parse(json: importJSON)

            id = imported.id
            name = imported.name
            applyImportedTransport(imported.transport)
            isImportSectionExpanded = false
        } catch {
            importError = formatJSONImportError(error)
            isImportSectionExpanded = true
        }
    }

    private func applyImportedTransport(_ transport: MCPTransportConfig) {
        switch transport {
        case .stdio(let stdio):
            transportKind = .stdio
            command = stdio.command
            args = CommandLineTokenizer.render(stdio.args)
            envPairs = stdio.env.keys.sorted().map { EnvironmentVariablePair(key: $0, value: stdio.env[$0] ?? "") }
        case .http(let http):
            transportKind = .http
            endpoint = http.endpoint.absoluteString
            applyHTTPAuthentication(http.authentication)
            headerPairs = http.additionalHeaders.map { EnvironmentVariablePair(key: $0.name, value: $0.value) }
            httpStreaming = http.streaming
        }
    }

    private func addServer() {
        let transport: MCPTransportConfig

        switch transportKind {
        case .stdio:
            let argsArray: [String]
            do {
                argsArray = try CommandLineTokenizer.tokenize(args)
            } catch {
                importError = error.localizedDescription
                return
            }

            let env: [String: String] = envPairs.reduce(into: [:]) { partial, pair in
                let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                partial[key] = pair.value
            }

            transport = .stdio(
                MCPStdioTransportConfig(
                    command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                    args: argsArray,
                    env: env
                )
            )

        case .http:
            guard let endpointURL = parsedEndpoint else {
                importError = "Invalid endpoint URL."
                return
            }
            guard let authentication = parsedHTTPAuthentication else {
                importError = httpAuthenticationValidationError ?? "Invalid authentication."
                return
            }

            let headers: [MCPHeader] = headerPairs.compactMap { pair in
                let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return nil }
                return MCPHeader(
                    name: key,
                    value: pair.value,
                    isSensitive: MCPHTTPTransportConfig.isSensitiveHeaderName(key)
                )
            }

            transport = .http(
                MCPHTTPTransportConfig(
                    endpoint: endpointURL,
                    streaming: httpStreaming,
                    authentication: authentication,
                    additionalHeaders: headers
                )
            )
        }

        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverID = trimmedID.isEmpty ? UUID().uuidString : trimmedID
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIconID = iconID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIconID: String? = {
            guard let trimmedIconID, !trimmedIconID.isEmpty else { return nil }
            if trimmedIconID.caseInsensitiveCompare(MCPIconCatalog.defaultIconID) == .orderedSame {
                return nil
            }
            return trimmedIconID
        }()
        let transportData = (try? JSONEncoder().encode(transport)) ?? Data()

        let server = MCPServerConfigEntity(
            id: serverID,
            name: trimmedName,
            iconID: normalizedIconID,
            transportKindRaw: transport.kind.rawValue,
            transportData: transportData,
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: true
        )
        do {
            try server.setTransport(transport)
        } catch {
            importError = "Failed to save transport config: \(error.localizedDescription)"
            return
        }

        modelContext.insert(server)
        dismiss()
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

    private func formatJSONImportError(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return decodingErrorDescription(decodingError)
        }

        if let importError = error as? MCPServerImportError {
            return importError.localizedDescription
        }

        return error.localizedDescription
    }

    private func decodingErrorDescription(_ error: DecodingError) -> String {
        func codingPathString(_ path: [CodingKey]) -> String {
            guard !path.isEmpty else { return "(root)" }
            return path.map(\.stringValue).joined(separator: ".")
        }

        switch error {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            return "\(context.debugDescription)\nPath: \(codingPathString(context.codingPath))"
        @unknown default:
            return error.localizedDescription
        }
    }
}
