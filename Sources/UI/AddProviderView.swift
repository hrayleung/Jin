import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AddProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var providerType: ProviderType = .openai
    @State private var iconID: String? = LobeProviderIconCatalog.defaultIconID(for: .openai)
    @State private var baseURL = ProviderType.openai.defaultBaseURL ?? ""
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""

    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)

                ProviderIconPickerField(
                    selectedIconID: $iconID,
                    defaultIconID: LobeProviderIconCatalog.defaultIconID(for: providerType)
                )

                Picker("Type", selection: $providerType) {
                    ForEach(ProviderType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: providerType) { oldValue, newValue in
                    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed == oldValue.defaultBaseURL {
                        baseURL = newValue.defaultBaseURL ?? ""
                    }

                    let oldDefaultIconID = LobeProviderIconCatalog.defaultIconID(for: oldValue)
                    let currentIconID = iconID?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentIconID == nil || currentIconID?.isEmpty == true || currentIconID == oldDefaultIconID {
                        iconID = LobeProviderIconCatalog.defaultIconID(for: newValue)
                    }
                }

                if providerType != .vertexai {
                    TextField("Base URL", text: $baseURL)
                        .help("Default endpoint is pre-filled.")
                }

                if providerType == .codexAppServer {
                    Text("Codex App Server expects a running `codex app-server --listen ws://127.0.0.1:4500` process.")
                        .jinInfoCallout()
                }

                switch providerType {
                case .codexAppServer:
                    VStack(alignment: .leading, spacing: 6) {
                        SecureField("API Key (Optional)", text: $apiKey)
                        Text("Leave blank to use ChatGPT account login in provider settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini:
                    SecureField("API Key", text: $apiKey)
                case .vertexai:
                    TextEditor(text: $serviceAccountJSON)
                        .frame(minHeight: 100)
                        .font(.system(.body, design: .monospaced))
                        .jinTextEditorField(cornerRadius: JinRadius.small)
                        .overlay(alignment: .topLeading) {
                            if serviceAccountJSON.isEmpty {
                                Text("Paste service account JSON here…")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if let saveError {
                    Text(saveError)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(JinSemanticColor.detailSurface)
            .navigationTitle("Add Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addProvider() }
                        .disabled(isAddDisabled)
                }
            }
            .frame(width: 500, height: 400)
        }
        #if os(macOS)
        .background(MovableWindowHelper())
        #endif
    }

    private func addProvider() {
        isSaving = true
        saveError = nil

        Task {
            do {
                let providerID = UUID().uuidString
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedServiceAccountJSON = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedIconID = iconID?.trimmingCharacters(in: .whitespacesAndNewlines)

                if providerType == .vertexai {
                    _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(trimmedServiceAccountJSON.utf8))
                }

                let config = ProviderConfig(
                    id: providerID,
                    name: trimmedName,
                    type: providerType,
                    iconID: trimmedIconID?.isEmpty == false ? trimmedIconID : nil,
                    apiKey: providerType == .vertexai ? nil : (trimmedAPIKey.isEmpty ? nil : trimmedAPIKey),
                    serviceAccountJSON: providerType == .vertexai ? trimmedServiceAccountJSON : nil,
                    baseURL: providerType == .vertexai ? nil : trimmedBaseURL.isEmpty ? nil : trimmedBaseURL
                )

                let entity = try ProviderConfigEntity.fromDomain(config)

                await MainActor.run {
                    modelContext.insert(entity)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }

    private var isAddDisabled: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !isSaving else { return true }

        switch providerType {
        case .codexAppServer:
            return false
        case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vertexai:
            return serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

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

        let serverID = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UUID().uuidString
            : id.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let transportData = (try? JSONEncoder().encode(transport)) ?? Data()

        let server = MCPServerConfigEntity(
            id: serverID,
            name: trimmedName,
            transportKindRaw: transport.kind.rawValue,
            transportData: transportData,
            lifecycleRaw: MCPLifecyclePolicy.persistent.rawValue,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: true
        )
        server.setTransport(transport)

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

#if os(macOS)
/// Sets `isMovableByWindowBackground = true` on the hosting NSWindow,
/// allowing the sheet to be dragged from any non-interactive area.
private struct MovableWindowHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = MovableWindowNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MovableWindowNSView: NSView {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isMovableByWindowBackground = true
    }
}
#endif
