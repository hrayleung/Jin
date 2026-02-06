import SwiftUI
import SwiftData

struct MCPServerConfigFormView: View {
    @Bindable var server: MCPServerConfigEntity

    @State private var argsText = ""
    @State private var argsError: String?
    @State private var envPairs: [EnvironmentVariablePair] = []
    @State private var disabledTools: Set<String> = []

    @State private var verifying = false
    @State private var verifyError: String?
    @State private var tools: [MCPToolInfo] = []
    @State private var schemaPresentedTool: MCPToolInfo?

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Type") {
                    Text("Command-line (stdio)")
                        .foregroundStyle(.secondary)
                }

                TextField("Name", text: $server.name)
                TextField("ID", text: $server.id)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .help("Keep this short to avoid tool name length limits (e.g. “exa”).")

                Toggle("Enabled", isOn: $server.isEnabled)
                Toggle("Run tools automatically", isOn: $server.runToolsAutomatically)
                Toggle("Long-running", isOn: $server.isLongRunning)
            }

            Section("Command") {
                TextField("Command", text: $server.command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                TextField("Arguments", text: $argsText)
                    .font(.system(.body, design: .monospaced))
                    .help("Space-separated. For complex quoting, prefer wrapping with a shell script.")

                if shouldShowNodeIsolationNote {
                    Text("Note: For Node-based launchers (e.g. `npx`), Jin runs the process with an isolated npm HOME/cache under Application Support to avoid `~/.npmrc`/permission issues. Override by setting `HOME` or `NPM_CONFIG_USERCONFIG` in Environment variables.")
                        .jinInfoCallout()
                }

                if isFirecrawlMCP && !hasFirecrawlAPIKey {
                    Text("Firecrawl MCP requires `FIRECRAWL_API_KEY` in Environment variables (otherwise the server may never respond to `initialize`).")
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
                        .disabled(verifying || server.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(JinSpacing.small)
                            .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
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
            }
        }
        .formStyle(.grouped)
        .padding()
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .task {
            loadArgs()
            loadEnv()
            loadDisabledTools()
        }
        .onChange(of: argsText) { _, newValue in
            do {
                let args = try CommandLineTokenizer.tokenize(newValue)
                argsError = nil
                server.setArgs(args)
            } catch {
                argsError = error.localizedDescription
            }
        }
        .onChange(of: envPairs) { _, _ in
            persistEnv()
        }
        .sheet(item: $schemaPresentedTool) { tool in
            NavigationStack {
                ScrollView {
                    if let schemaText = formattedSchemaText(tool.inputSchema) {
                        Text(schemaText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(JinSpacing.medium)
                            .jinSurface(.raised, cornerRadius: JinRadius.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No schema available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(JinSpacing.medium)
                            .jinSurface(.raised, cornerRadius: JinRadius.medium)
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
    }

    private func loadArgs() {
        let args: [String] = (try? JSONDecoder().decode([String].self, from: server.argsData)) ?? []
        argsText = CommandLineTokenizer.render(args)
    }

    private func loadEnv() {
        let env: [String: String] = server.envData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        envPairs = env.keys.sorted().map { EnvironmentVariablePair(key: $0, value: env[$0] ?? "") }
    }

    private func loadDisabledTools() {
        disabledTools = server.disabledTools()
    }

    private func persistEnv() {
        var env: [String: String] = [:]
        for pair in envPairs {
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            env[key] = pair.value
        }
        server.setEnv(env)
    }

    private func verifyTools() {
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
        let trimmed = server.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCommand = (try? CommandLineTokenizer.tokenize(trimmed))?.first ?? trimmed
        let base = (parsedCommand as NSString).lastPathComponent.lowercased()
        return ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains(base)
    }

    private var isFirecrawlMCP: Bool {
        let cmd = server.command.lowercased()
        if cmd.contains("firecrawl-mcp") { return true }

        let args: [String] = (try? JSONDecoder().decode([String].self, from: server.argsData)) ?? []
        return args.contains { $0.lowercased() == "firecrawl-mcp" }
    }

    private var hasFirecrawlAPIKey: Bool {
        envPairs.contains { pair in
            pair.key.trimmingCharacters(in: .whitespacesAndNewlines) == "FIRECRAWL_API_KEY"
                && !pair.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
        .jinSurface(.raised, cornerRadius: JinRadius.medium)
    }
}
