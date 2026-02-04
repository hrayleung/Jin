import SwiftUI
import SwiftData

struct MCPServerConfigFormView: View {
    @Bindable var server: MCPServerConfigEntity

    @State private var argsText = ""
    @State private var argsError: String?
    @State private var envPairs: [EnvironmentVariablePair] = []

    @State private var verifying = false
    @State private var verifyError: String?
    @State private var tools: [MCPToolInfo] = []
    @State private var showingToolsSheet = false

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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isFirecrawlMCP && !hasFirecrawlAPIKey {
                    Text("Firecrawl MCP requires `FIRECRAWL_API_KEY` in Environment variables (otherwise the server may never respond to `initialize`).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    }

                    if let verifyError {
                        Text(verifyError)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            loadArgs()
            loadEnv()
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
        .sheet(isPresented: $showingToolsSheet) {
            NavigationStack {
                List {
                    ForEach(tools, id: \.name) { tool in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tool.name)
                                .font(.headline)
                            if !tool.description.isEmpty {
                                Text(tool.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let schemaText = formattedSchemaText(tool.inputSchema) {
                                DisclosureGroup("Input schema") {
                                    Text(schemaText)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(nsColor: .textBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle("Tools (\(tools.count))")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") { showingToolsSheet = false }
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
                    self.showingToolsSheet = true
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
