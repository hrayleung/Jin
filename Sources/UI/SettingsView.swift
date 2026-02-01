import SwiftUI
import SwiftData

struct SettingsView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case providers = "Providers"
        case mcpServers = "MCP Servers"
        case general = "General"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .providers: return "network"
            case .mcpServers: return "server.rack"
            case .general: return "gearshape"
            }
        }
    }

    @State private var selectedSection: SettingsSection? = .providers
    @State private var selectedProviderID: String?
    @State private var selectedServerID: String?
    @State private var searchText = ""

    // Queries for lists
    @Query(sort: \ProviderConfigEntity.name) private var providers: [ProviderConfigEntity]
    @Query(sort: \MCPServerConfigEntity.name) private var mcpServers: [MCPServerConfigEntity]

    // State for modals
    @State private var showingAddProvider = false
    @State private var showingAddServer = false

    var body: some View {
        NavigationSplitView {
            // Column 1: Navigation Sidebar
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.systemImage)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")

        } content: {
            // Column 2: List (Contextual)
            VStack(spacing: 0) {
                switch selectedSection {
                case .providers:
                    providersList
                case .mcpServers:
                    mcpServersList
                case .general, .none:
                    Text("General")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    Spacer()
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 260)
            .toolbar {
                if selectedSection == .providers {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddProvider = true
                        } label: {
                            Label("Add Provider", systemImage: "plus")
                        }
                    }
                } else if selectedSection == .mcpServers {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddServer = true
                        } label: {
                            Label("Add Server", systemImage: "plus")
                        }
                    }
                }
            }

        } detail: {
            // Column 3: Configuration / Detail
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                    .ignoresSafeArea()
                
                switch selectedSection {
                case .providers:
                    if let id = selectedProviderID, let provider = providers.first(where: { $0.id == id }) {
                        ProviderConfigFormView(provider: provider)
                            .id(id) // Force refresh
                    } else {
                        ContentUnavailableView("Select a Provider", systemImage: "network")
                    }
                case .mcpServers:
                    if let id = selectedServerID, let server = mcpServers.first(where: { $0.id == id }) {
                        MCPServerConfigFormView(server: server)
                            .id(id)
                    } else {
                        ContentUnavailableView("Select an MCP Server", systemImage: "server.rack")
                    }
                case .general, .none:
                    GeneralSettingsView()
                }
            }
            .navigationSplitViewColumnWidth(min: 520, ideal: 640)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 920, minHeight: 600)
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView()
        }
        .sheet(isPresented: $showingAddServer) {
            AddMCPServerView()
        }
        .onAppear {
            if selectedProviderID == nil {
                selectedProviderID = providers.first?.id
            }
        }
    }

    // MARK: - Providers List
    private var providersList: some View {
        List(providers, selection: $selectedProviderID) { provider in
            NavigationLink(value: provider.id) {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                        Text(ProviderType(rawValue: provider.typeRaw)?.displayName ?? provider.typeRaw)
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
    }

    // MARK: - MCP Servers List
    private var mcpServersList: some View {
        List(mcpServers, selection: $selectedServerID) { server in
            NavigationLink(value: server.id) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(server.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                        Text(server.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
    }
}

// Keeping the existing Add Views and General View structure but styled up a bit if needed.
// For brevity and minimal conflict, I'll rely on the existing AddProviderView and AddMCPServerView structs
// but I need to make sure they are available. I will re-include them or ensure they are in the file.
// Since I am overwriting the file, I must include them.

struct AddProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var providerType: ProviderType = .openai
    @State private var baseURL = ProviderType.openai.defaultBaseURL ?? ""
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""

    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                
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
                }

                if providerType != .vertexai {
                    TextField("Base URL", text: $baseURL)
                        .help("Default endpoint is pre-filled.")
                }

                switch providerType {
                case .openai, .anthropic, .xai:
                    SecureField("API Key", text: $apiKey)
                case .vertexai:
                    TextEditor(text: $serviceAccountJSON)
                        .frame(minHeight: 100)
                        .font(.system(.body, design: .monospaced))
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

                let config = ProviderConfig(
                    id: providerID,
                    name: trimmedName,
                    type: providerType,
                    apiKey: providerType == .vertexai ? nil : trimmedAPIKey.isEmpty ? nil : trimmedAPIKey,
                    serviceAccountJSON: providerType == .vertexai ? trimmedServiceAccountJSON.isEmpty ? nil : trimmedServiceAccountJSON : nil,
                    baseURL: providerType == .vertexai ? nil : trimmedBaseURL.isEmpty ? nil : trimmedBaseURL
                )

                if providerType == .vertexai, let json = config.serviceAccountJSON {
                    _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(json.utf8))
                }

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
        case .openai, .anthropic, .xai:
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
        case exaLocal = "Exa (Local via npx)"
        case exaRemote = "Exa (Remote via mcp-remote)"

        var id: String { rawValue }
    }

    private struct ImportedServer {
        let id: String
        let name: String
        let command: String
        let args: [String]
        let env: [String: String]
    }

    @State private var id = ""
    @State private var name = ""
    @State private var command = ""
    @State private var args = ""
    @State private var envPairs: [EnvPair] = []
    @State private var runToolsAutomatically = true
    @State private var isLongRunning = false
    @State private var isEnabled = true

    @State private var preset: Preset = .custom
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
                            .overlay(alignment: .topLeading) {
                                if importJSON.isEmpty {
                                    Text("{ \"mcpServers\": { \"exa\": { \"command\": \"npx\", \"args\": [\"-y\", \"exa-mcp-server\"], \"env\": { \"EXA_API_KEY\": \"…\" } } } }")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }

                        if let importError {
                            Text(importError)
                                .foregroundStyle(.red)
                                .font(.caption)
                        } else {
                            Text("Supports Claude Desktop-style configs (`mcpServers`) and single-server configs (`command`, `args`, `env`).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                TextField("ID", text: $id)
                    .help("Short identifier (e.g. 'git').")
                TextField("Name", text: $name)
                TextField("Command", text: $command)
                TextField("Arguments", text: $args)

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                    Toggle("Run tools automatically", isOn: $runToolsAutomatically)
                    Toggle("Long-running", isOn: $isLongRunning)
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
            }
            .formStyle(.grouped)
            .navigationTitle("Add MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addServer() }
                        .disabled(name.isEmpty || command.isEmpty)
                }
            }
            .frame(width: 560, height: 680)
        }
    }

    private func applyPreset(_ preset: Preset) {
        importError = nil

        switch preset {
        case .custom:
            break
        case .exaLocal:
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { id = "exa" }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "Exa" }
            command = "npx"
            args = "-y exa-mcp-server"
            if envPairs.first(where: { $0.key == "EXA_API_KEY" }) == nil {
                envPairs.append(EnvPair(key: "EXA_API_KEY", value: ""))
            }
        case .exaRemote:
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { id = "exa" }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "Exa (Remote)" }
            command = "npx"
            args = "-y mcp-remote https://mcp.exa.ai/mcp?exaApiKey=YOUR_EXA_API_KEY"
        }
    }

    private func importFromJSON() {
        importError = nil

        do {
            let data = Data(importJSON.utf8)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let imported = try parseImportedServer(object) else {
                importError = "Unsupported JSON format."
                return
            }

            id = imported.id
            name = imported.name
            command = imported.command
            args = imported.args.joined(separator: " ")
            envPairs = imported.env.keys.sorted().map { EnvPair(key: $0, value: imported.env[$0] ?? "") }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func parseImportedServer(_ object: Any) throws -> ImportedServer? {
        guard let dict = object as? [String: Any] else { return nil }

        // Claude Desktop-style config: { "mcpServers": { "<id>": { "command": "...", "args": [...], "env": {...} } } }
        if let mcpServers = dict["mcpServers"] as? [String: Any] {
            if let explicitID = dict["id"] as? String,
               let serverDict = mcpServers[explicitID] as? [String: Any] {
                return try parseSingleServer(id: explicitID, nameOverride: dict["name"] as? String, serverDict: serverDict)
            }

            if let (serverID, rawServer) = mcpServers.first,
               let serverDict = rawServer as? [String: Any] {
                return try parseSingleServer(id: serverID, nameOverride: nil, serverDict: serverDict)
            }
        }

        // Single-server config: { "id": "...", "name": "...", "command": "...", "args": [...], "env": {...} }
        if let command = dict["command"] as? String {
            let serverID = (dict["id"] as? String) ?? UUID().uuidString
            let serverName = (dict["name"] as? String) ?? serverID

            if let type = dict["type"] as? String, type.lowercased() == "http", let url = dict["url"] as? String {
                // HTTP MCP server via the mcp-remote bridge (stdio)
                return ImportedServer(
                    id: serverID,
                    name: serverName,
                    command: "npx",
                    args: ["-y", "mcp-remote", url],
                    env: [:]
                )
            }

            let args = (dict["args"] as? [String]) ?? []
            let env = (dict["env"] as? [String: String]) ?? [:]

            return ImportedServer(id: serverID, name: serverName, command: command, args: args, env: env)
        }

        return nil
    }

    private func parseSingleServer(id: String, nameOverride: String?, serverDict: [String: Any]) throws -> ImportedServer? {
        if let type = serverDict["type"] as? String, type.lowercased() == "http", let url = serverDict["url"] as? String {
            return ImportedServer(
                id: id,
                name: nameOverride ?? id,
                command: "npx",
                args: ["-y", "mcp-remote", url],
                env: [:]
            )
        }

        guard let command = serverDict["command"] as? String else { return nil }
        let args = (serverDict["args"] as? [String]) ?? []
        let env = (serverDict["env"] as? [String: String]) ?? [:]
        return ImportedServer(id: id, name: nameOverride ?? id, command: command, args: args, env: env)
    }

    private func addServer() {
        let argsArray = args.split(separator: " ").map(String.init)
        let argsData = (try? JSONEncoder().encode(argsArray)) ?? Data()
        let env: [String: String] = envPairs.reduce(into: [:]) { partial, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partial[key] = pair.value
        }
        let envData = env.isEmpty ? nil : (try? JSONEncoder().encode(env))

        let serverID = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UUID().uuidString
            : id.trimmingCharacters(in: .whitespacesAndNewlines)

        let server = MCPServerConfigEntity(
            id: serverID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            command: command.trimmingCharacters(in: .whitespacesAndNewlines),
            argsData: argsData,
            envData: envData,
            isEnabled: isEnabled,
            runToolsAutomatically: runToolsAutomatically,
            isLongRunning: isLongRunning
        )

        modelContext.insert(server)
        dismiss()
    }
}

private struct EnvPair: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}

struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [ConversationEntity]

    @State private var showingDeleteAllChatsConfirmation = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Always show in menu bar", isOn: .constant(true))
                Picker("Theme", selection: .constant("System")) {
                    Text("System").tag("System")
                    Text("Dark").tag("Dark")
                    Text("Light").tag("Light")
                }
            }
            
            Section("Data") {
                Button("Clear All Caches") {}
                Button("Reset All Settings") {}
                Button("Delete All Chats", role: .destructive) {
                    showingDeleteAllChatsConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog("Delete all chats?", isPresented: $showingDeleteAllChatsConfirmation) {
            Button("Delete All Chats", role: .destructive) {
                deleteAllChats()
            }
        } message: {
            Text("This will permanently delete all chats across all assistants.")
        }
    }

    private func deleteAllChats() {
        for conversation in conversations {
            modelContext.delete(conversation)
        }
    }
}
