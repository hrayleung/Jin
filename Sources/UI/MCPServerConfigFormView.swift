import SwiftUI
import SwiftData

struct MCPServerConfigFormView: View {
    @Bindable var server: MCPServerConfigEntity

    @State private var argsText = ""
    @State private var envPairs: [EnvPair] = []

    @State private var verifying = false
    @State private var verifyError: String?
    @State private var tools: [MCPToolInfo] = []
    @State private var showingToolsSheet = false

    var body: some View {
        Form {
            Section("Server") {
                Picker("Type", selection: .constant("stdio")) {
                    Text("Command-line (stdio)").tag("stdio")
                }
                .disabled(true)

                TextField("Name", text: $server.name)
                TextField("ID", text: $server.id)
                    .textSelection(.enabled)
                    .help("Keep this short to avoid tool name length limits (e.g. “exa”).")

                Toggle("Enabled", isOn: $server.isEnabled)
                Toggle("Run tools automatically", isOn: $server.runToolsAutomatically)
                Toggle("Long-running", isOn: $server.isLongRunning)
            }

            Section("Command") {
                TextField("Command", text: $server.command)
                TextField("Arguments", text: $argsText)
                    .help("Space-separated. For complex quoting, prefer wrapping with a shell script.")
            }

            Section("Environment variables") {
                if envPairs.isEmpty {
                    Text("No environment variables")
                        .foregroundColor(.secondary)
                } else {
                    ForEach($envPairs) { $pair in
                        HStack {
                            TextField("KEY", text: $pair.key)
                                .font(.system(.body, design: .monospaced))
                            TextField("VALUE", text: $pair.value)
                                .font(.system(.body, design: .monospaced))
                            Button(role: .destructive) {
                                envPairs.removeAll { $0.id == pair.id }
                                persistEnv()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    envPairs.append(EnvPair(key: "", value: ""))
                } label: {
                    Label("Add variable", systemImage: "plus")
                }
            }

            Section("Tools") {
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

                    if let verifyError {
                        Text(verifyError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
        }
        .task {
            loadArgs()
            loadEnv()
        }
        .onChange(of: argsText) { _, newValue in
            let args = newValue.split(separator: " ").map(String.init)
            server.setArgs(args)
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
        argsText = args.joined(separator: " ")
    }

    private func loadEnv() {
        let env: [String: String] = server.envData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        envPairs = env.keys.sorted().map { EnvPair(key: $0, value: env[$0] ?? "") }
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
}

private struct EnvPair: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}
