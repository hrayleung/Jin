import SwiftUI
import SwiftData
import Combine

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [ConversationEntity]

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case providers = "Providers"
        case mcpServers = "MCP Servers"
        case plugins = "Plugins"
        case general = "General"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .providers: return "network"
            case .mcpServers: return "server.rack"
            case .plugins: return "puzzlepiece.extension"
            case .general: return "gearshape"
            }
        }
    }

    private struct PluginDescriptor: Identifiable, Hashable {
        let id: String
        let name: String
        let systemImage: String
        let summary: String
    }

    private static let availablePlugins: [PluginDescriptor] = [
        PluginDescriptor(
            id: "text_to_speech",
            name: "Text to Speech",
            systemImage: "speaker.wave.2",
            summary: "Play assistant messages aloud (ElevenLabs, OpenAI, Groq)."
        ),
        PluginDescriptor(
            id: "speech_to_text",
            name: "Speech to Text",
            systemImage: "mic",
            summary: "Dictate messages via transcription (Groq, OpenAI)."
        ),
        PluginDescriptor(
            id: "mistral_ocr",
            name: "Mistral OCR",
            systemImage: "doc.text.magnifyingglass",
            summary: "OCR PDFs for models without native PDF support."
        ),
        PluginDescriptor(
            id: "deepseek_ocr",
            name: "DeepSeek OCR (DeepInfra)",
            systemImage: "doc.text.magnifyingglass",
            summary: "OCR PDFs via DeepInfra-hosted DeepSeek-OCR."
        )
    ]

    @State private var selectedSection: SettingsSection? = .providers
    @State private var selectedProviderID: String?
    @State private var selectedServerID: String?
    @State private var selectedPluginID: String?
    @State private var searchText = ""
    @State private var providerPendingDeletion: ProviderConfigEntity?
    @State private var showingDeleteProviderConfirmation = false
    @State private var serverPendingDeletion: MCPServerConfigEntity?
    @State private var showingDeleteServerConfirmation = false
    @State private var operationErrorMessage: String?
    @State private var showingOperationError = false
    @State private var mistralOCRConfigured = false
    @State private var deepSeekOCRConfigured = false
    @State private var textToSpeechConfigured = false
    @State private var speechToTextConfigured = false

    // Queries for lists
    @Query(sort: \ProviderConfigEntity.name) private var providers: [ProviderConfigEntity]
    @Query(sort: \MCPServerConfigEntity.name) private var mcpServers: [MCPServerConfigEntity]

    // State for modals
    @State private var showingAddProvider = false
    @State private var showingAddServer = false

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredProviders: [ProviderConfigEntity] {
        let needle = trimmedSearchText
        guard !needle.isEmpty else { return providers }

        return providers.filter { provider in
            let typeName = ProviderType(rawValue: provider.typeRaw)?.displayName ?? provider.typeRaw
            return provider.name.localizedCaseInsensitiveContains(needle)
                || provider.typeRaw.localizedCaseInsensitiveContains(needle)
                || typeName.localizedCaseInsensitiveContains(needle)
                || (provider.baseURL ?? "").localizedCaseInsensitiveContains(needle)
        }
    }

    private var filteredMCPServers: [MCPServerConfigEntity] {
        let needle = trimmedSearchText
        guard !needle.isEmpty else { return mcpServers }

        return mcpServers.filter { server in
            return server.name.localizedCaseInsensitiveContains(needle)
                || server.id.localizedCaseInsensitiveContains(needle)
                || server.command.localizedCaseInsensitiveContains(needle)
        }
    }

    private var filteredPlugins: [PluginDescriptor] {
        let needle = trimmedSearchText
        guard !needle.isEmpty else { return Self.availablePlugins }

        return Self.availablePlugins.filter { plugin in
            plugin.name.localizedCaseInsensitiveContains(needle)
                || plugin.summary.localizedCaseInsensitiveContains(needle)
        }
    }

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
                    providersListWithActions
                case .mcpServers:
                    mcpServersListWithActions
                case .plugins:
                    pluginsList
                case .general, .none:
                    Text("General")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    Spacer()
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 260)

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
                case .plugins:
                    if selectedPluginID == "mistral_ocr" {
                        MistralOCRPluginSettingsView()
                            .id("mistral_ocr")
                    } else if selectedPluginID == "deepseek_ocr" {
                        DeepSeekOCRPluginSettingsView()
                            .id("deepseek_ocr")
                    } else if selectedPluginID == "text_to_speech" {
                        TextToSpeechPluginSettingsView()
                            .id("text_to_speech")
                    } else if selectedPluginID == "speech_to_text" {
                        SpeechToTextPluginSettingsView()
                            .id("speech_to_text")
                    } else {
                        ContentUnavailableView("Select a Plugin", systemImage: "puzzlepiece.extension")
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
            ensureValidSelection()
        }
        .onChange(of: searchText) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: selectedSection) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: providers.count) { _, _ in
            ensureValidSelection()
        }
        .onChange(of: mcpServers.count) { _, _ in
            ensureValidSelection()
        }
        .alert("Error", isPresented: $showingOperationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationErrorMessage ?? "Something went wrong.")
        }
        .task {
            await refreshPluginStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pluginCredentialsDidChange)) { _ in
            Task {
                await refreshPluginStatus()
            }
        }
        .confirmationDialog(
            "Delete provider?",
            isPresented: $showingDeleteProviderConfirmation,
            presenting: providerPendingDeletion
        ) { provider in
            Button("Delete", role: .destructive) {
                deleteProvider(provider)
            }
        } message: { provider in
            Text(providerDeletionMessage(provider))
        }
        .confirmationDialog(
            "Delete MCP server?",
            isPresented: $showingDeleteServerConfirmation,
            presenting: serverPendingDeletion
        ) { server in
            Button("Delete", role: .destructive) {
                deleteServer(server)
            }
        } message: { server in
            Text("This will permanently delete “\(server.name)”.")
        }
    }

    private func refreshPluginStatus() async {
        let keychainManager = KeychainManager()
        let mistralConfigured = await keychainManager.hasAPIKey(for: MistralOCRClient.Constants.keychainID)
        let deepSeekConfigured = await keychainManager.hasAPIKey(for: DeepInfraDeepSeekOCRClient.Constants.keychainID)

        let ttsProvider = TextToSpeechProvider(rawValue: UserDefaults.standard.string(forKey: AppPreferenceKeys.ttsProvider) ?? TextToSpeechProvider.openai.rawValue)
            ?? .openai
        let sttProvider = SpeechToTextProvider(rawValue: UserDefaults.standard.string(forKey: AppPreferenceKeys.sttProvider) ?? SpeechToTextProvider.groq.rawValue)
            ?? .groq

        let ttsKeychainID: String = {
            switch ttsProvider {
            case .elevenlabs:
                return ElevenLabsTTSClient.Constants.keychainID
            case .openai:
                return OpenAIAudioClient.Constants.keychainID
            case .groq:
                return GroqAudioClient.Constants.keychainID
            }
        }()

        let sttKeychainID: String = {
            switch sttProvider {
            case .openai:
                return OpenAIAudioClient.Constants.keychainID
            case .groq:
                return GroqAudioClient.Constants.keychainID
            }
        }()

        let ttsKeyConfigured = await keychainManager.hasAPIKey(for: ttsKeychainID)
        let sttConfigured = await keychainManager.hasAPIKey(for: sttKeychainID)

        let ttsConfigured: Bool
        if ttsProvider == .elevenlabs {
            let voiceID = (UserDefaults.standard.string(forKey: AppPreferenceKeys.ttsElevenLabsVoiceID) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ttsConfigured = ttsKeyConfigured && !voiceID.isEmpty
        } else {
            ttsConfigured = ttsKeyConfigured
        }

        await MainActor.run {
            mistralOCRConfigured = mistralConfigured
            deepSeekOCRConfigured = deepSeekConfigured
            textToSpeechConfigured = ttsConfigured
            speechToTextConfigured = sttConfigured
        }
    }

    // MARK: - Providers List
    private var providersList: some View {
        List(filteredProviders, selection: $selectedProviderID) { provider in
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
            .contextMenu {
                Button(role: .destructive) {
                    requestDeleteProvider(provider)
                } label: {
                    Label("Delete Provider", systemImage: "trash")
                }
            }
        }
        .listStyle(.inset)
        .onDeleteCommand {
            requestDeleteSelectedProvider()
        }
        .overlay {
            if !trimmedSearchText.isEmpty, filteredProviders.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
    }

    // MARK: - Plugins List
    private var pluginsList: some View {
        List(filteredPlugins, selection: $selectedPluginID) { plugin in
            NavigationLink(value: plugin.id) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(isPluginConfigured(plugin.id) ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .frame(width: 20)

                    Image(systemName: plugin.systemImage)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.name)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                        Text(plugin.summary)
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .overlay {
            if !trimmedSearchText.isEmpty, filteredPlugins.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
    }

    private func isPluginConfigured(_ pluginID: String) -> Bool {
        switch pluginID {
        case "mistral_ocr":
            return mistralOCRConfigured
        case "deepseek_ocr":
            return deepSeekOCRConfigured
        case "text_to_speech":
            return textToSpeechConfigured
        case "speech_to_text":
            return speechToTextConfigured
        default:
            return false
        }
    }

    private var providersListWithActions: some View {
        VStack(spacing: 0) {
            providersList

            Divider()

            HStack {
                Button {
                    showingAddProvider = true
                } label: {
                    Label("Add Provider", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    requestDeleteSelectedProvider()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(selectedProviderID == nil)
                .keyboardShortcut(.delete, modifiers: [.command])
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - MCP Servers List
    private var mcpServersList: some View {
        List(filteredMCPServers, selection: $selectedServerID) { server in
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
            .contextMenu {
                Button(role: .destructive) {
                    requestDeleteServer(server)
                } label: {
                    Label("Delete Server", systemImage: "trash")
                }
            }
        }
        .listStyle(.inset)
        .onDeleteCommand {
            requestDeleteSelectedServer()
        }
        .overlay {
            if !trimmedSearchText.isEmpty, filteredMCPServers.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
    }

    private var mcpServersListWithActions: some View {
        VStack(spacing: 0) {
            mcpServersList

            Divider()

            HStack {
                Button {
                    showingAddServer = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    requestDeleteSelectedServer()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(selectedServerID == nil)
                .keyboardShortcut(.delete, modifiers: [.command])
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func showOperationError(_ message: String) {
        operationErrorMessage = message
        showingOperationError = true
    }

    private func providerDeletionMessage(_ provider: ProviderConfigEntity) -> String {
        let count = conversations.filter { $0.providerID == provider.id }.count
        guard count > 0 else {
            return "This will permanently delete “\(provider.name)”."
        }

        return """
        This will permanently delete “\(provider.name)”.

        It is currently used by \(count) chat\(count == 1 ? "" : "s"). Those chats will need a different provider selected.
        """
    }

    private func requestDeleteSelectedProvider() {
        guard let selectedProviderID,
              let provider = providers.first(where: { $0.id == selectedProviderID }) else {
            return
        }
        requestDeleteProvider(provider)
    }

    private func requestDeleteProvider(_ provider: ProviderConfigEntity) {
        guard providers.count > 1 else {
            showOperationError("You must keep at least one provider configured.")
            return
        }

        providerPendingDeletion = provider
        showingDeleteProviderConfirmation = true
    }

    private func deleteProvider(_ provider: ProviderConfigEntity) {
        Task { @MainActor in
            let keychainID = (provider.apiKeyKeychainID ?? provider.id).trimmingCharacters(in: .whitespacesAndNewlines)
            if !keychainID.isEmpty {
                let keychainManager = KeychainManager()
                _ = try? await keychainManager.deleteAPIKey(for: keychainID)
                _ = try? await keychainManager.deleteServiceAccountJSON(for: keychainID)
            }

            modelContext.delete(provider)
            providerPendingDeletion = nil
        }
    }

    private func requestDeleteSelectedServer() {
        guard let selectedServerID,
              let server = mcpServers.first(where: { $0.id == selectedServerID }) else {
            return
        }
        requestDeleteServer(server)
    }

    private func requestDeleteServer(_ server: MCPServerConfigEntity) {
        serverPendingDeletion = server
        showingDeleteServerConfirmation = true
    }

    private func deleteServer(_ server: MCPServerConfigEntity) {
        Task { @MainActor in
            modelContext.delete(server)
            serverPendingDeletion = nil
        }
    }

    private func ensureValidSelection() {
        if selectedSection == nil {
            selectedSection = .providers
        }

        switch selectedSection {
        case .providers:
            selectedServerID = nil
            selectedPluginID = nil
            let candidates = filteredProviders
            if let selectedProviderID,
               candidates.contains(where: { $0.id == selectedProviderID }) {
                return
            }
            selectedProviderID = candidates.first?.id
        case .mcpServers:
            selectedProviderID = nil
            selectedPluginID = nil
            let candidates = filteredMCPServers
            if let selectedServerID,
               candidates.contains(where: { $0.id == selectedServerID }) {
                return
            }
            selectedServerID = candidates.first?.id
        case .plugins:
            selectedProviderID = nil
            selectedServerID = nil
            let candidates = filteredPlugins
            if let selectedPluginID,
               candidates.contains(where: { $0.id == selectedPluginID }) {
                return
            }
            selectedPluginID = candidates.first?.id
        case .general:
            selectedProviderID = nil
            selectedServerID = nil
            selectedPluginID = nil
        case .none:
            selectedSection = .providers
        }
    }
}

struct AddProviderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var providerType: ProviderType = .openai
    @State private var baseURL = ProviderType.openai.defaultBaseURL ?? ""
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""
    @State private var storeCredentialsInKeychain = true

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

                Toggle("Store credentials in Keychain", isOn: $storeCredentialsInKeychain)
                    .help("Keychain is more secure, but unsigned builds may prompt for your Mac password.")

                switch providerType {
                case .openai, .anthropic, .xai, .fireworks, .cerebras:
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

                let config: ProviderConfig
                if storeCredentialsInKeychain {
                    let keychainManager = KeychainManager()
                    switch providerType {
                    case .openai, .anthropic, .xai, .fireworks, .cerebras:
                        try await keychainManager.saveAPIKey(trimmedAPIKey, for: providerID)
                    case .vertexai:
                        _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(trimmedServiceAccountJSON.utf8))
                        try await keychainManager.saveServiceAccountJSON(trimmedServiceAccountJSON, for: providerID)
                    }

                    config = ProviderConfig(
                        id: providerID,
                        name: trimmedName,
                        type: providerType,
                        apiKey: nil,
                        serviceAccountJSON: nil,
                        apiKeyKeychainID: providerID,
                        baseURL: providerType == .vertexai ? nil : trimmedBaseURL.isEmpty ? nil : trimmedBaseURL
                    )
                } else {
                    if providerType == .vertexai {
                        _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(trimmedServiceAccountJSON.utf8))
                    }

                    config = ProviderConfig(
                        id: providerID,
                        name: trimmedName,
                        type: providerType,
                        apiKey: providerType == .vertexai ? nil : trimmedAPIKey,
                        serviceAccountJSON: providerType == .vertexai ? trimmedServiceAccountJSON : nil,
                        apiKeyKeychainID: nil,
                        baseURL: providerType == .vertexai ? nil : trimmedBaseURL.isEmpty ? nil : trimmedBaseURL
                    )
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
        case .openai, .anthropic, .xai, .fireworks, .cerebras:
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
        case firecrawlLocal = "Firecrawl (Local via npx)"

        var id: String { rawValue }
    }

    @State private var id = ""
    @State private var name = ""
    @State private var command = ""
    @State private var args = ""
    @State private var envPairs: [EnvironmentVariablePair] = []
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
                    EnvironmentVariablesEditor(pairs: $envPairs)
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
                envPairs.append(EnvironmentVariablePair(key: "EXA_API_KEY", value: ""))
            }
        case .exaRemote:
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { id = "exa" }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "Exa (Remote)" }
            command = "npx"
            args = "-y mcp-remote https://mcp.exa.ai/mcp?exaApiKey=YOUR_EXA_API_KEY"
        case .firecrawlLocal:
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { id = "firecrawl" }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "Firecrawl" }
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
            command = imported.command
            args = CommandLineTokenizer.render(imported.args)
            envPairs = imported.env.keys.sorted().map { EnvironmentVariablePair(key: $0, value: imported.env[$0] ?? "") }
        } catch {
            importError = formatJSONImportError(error)
        }
    }

    private func addServer() {
        let argsArray: [String]
        do {
            argsArray = try CommandLineTokenizer.tokenize(args)
        } catch {
            importError = error.localizedDescription
            return
        }
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

struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [ConversationEntity]
    @Query(sort: \ProviderConfigEntity.name) private var providers: [ProviderConfigEntity]
    @Query(sort: \MCPServerConfigEntity.name) private var mcpServers: [MCPServerConfigEntity]

    @State private var showingDeleteAllChatsConfirmation = false
    @AppStorage(AppPreferenceKeys.newChatModelMode) private var newChatModelMode: NewChatModelMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedProviderID) private var newChatFixedProviderID = "openai"
    @AppStorage(AppPreferenceKeys.newChatFixedModelID) private var newChatFixedModelID = "gpt-5.2"
    @AppStorage(AppPreferenceKeys.newChatMCPMode) private var newChatMCPMode: NewChatMCPMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedMCPEnabled) private var newChatFixedMCPEnabled = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPUseAllServers) private var newChatFixedMCPUseAllServers = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPServerIDsJSON) private var newChatFixedMCPServerIDsJSON = "[]"

    var body: some View {
        Form {
            Section("New Chat Defaults") {
                Picker("Model", selection: $newChatModelMode) {
                    ForEach(NewChatModelMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if newChatModelMode == .fixed {
                    Picker("Provider", selection: $newChatFixedProviderID) {
                        ForEach(providers, id: \.id) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .onChange(of: newChatFixedProviderID) { _, _ in
                        ensureValidFixedModelSelection()
                    }

                    let models = modelsForProvider(newChatFixedProviderID)
                    if models.isEmpty {
                        Text("No models found for this provider.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Model", selection: $newChatFixedModelID) {
                            ForEach(models) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .onChange(of: newChatFixedModelID) { _, _ in
                            ensureValidFixedModelSelection()
                        }
                    }
                } else {
                    Text("New chats will start with the model from your most recently used chat.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("New Chat MCP Defaults") {
                Picker("MCP Tools", selection: $newChatMCPMode) {
                    ForEach(NewChatMCPMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if newChatMCPMode == .fixed {
                    Toggle("Enable MCP Tools by default", isOn: $newChatFixedMCPEnabled)

                    if newChatFixedMCPEnabled {
                        Toggle("Use all enabled servers", isOn: $newChatFixedMCPUseAllServers)
                            .onChange(of: newChatFixedMCPUseAllServers) { _, isOn in
                                guard !isOn else { return }
                                let current = AppPreferences.decodeStringArrayJSON(newChatFixedMCPServerIDsJSON)
                                guard current.isEmpty else { return }
                                let eligibleIDs = eligibleMCPServers.map(\.id)
                                newChatFixedMCPServerIDsJSON = AppPreferences.encodeStringArrayJSON(eligibleIDs)
                            }

                        if !newChatFixedMCPUseAllServers {
                            let eligibleServers = eligibleMCPServers
                            if eligibleServers.isEmpty {
                                Text("No eligible MCP servers. Enable servers in MCP Servers settings.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Default servers")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(eligibleServers, id: \.id) { server in
                                        Toggle(server.name, isOn: fixedMCPServerBinding(serverID: server.id))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                } else {
                    Text("New chats will copy MCP Tools settings from your most recently used chat.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                Text("These actions affect local data stored on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent("Chats") {
                    Text("\(conversations.count)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button("Delete All Chats", role: .destructive) {
                    showingDeleteAllChatsConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            ensureValidFixedModelSelection()
        }
        .confirmationDialog("Delete all chats?", isPresented: $showingDeleteAllChatsConfirmation) {
            Button("Delete All Chats", role: .destructive) {
                deleteAllChats()
            }
        } message: {
            Text("This will permanently delete all chats across all assistants.")
        }
    }

    private var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func modelsForProvider(_ providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }),
              let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData) else {
            return []
        }
        return models
    }

    private func ensureValidFixedModelSelection() {
        guard newChatModelMode == .fixed else { return }

        if providers.first(where: { $0.id == newChatFixedProviderID }) == nil {
            newChatFixedProviderID = providers.first(where: { $0.id == "openai" })?.id
                ?? providers.first?.id
                ?? "openai"
        }

        let models = modelsForProvider(newChatFixedProviderID)
        guard !models.isEmpty else { return }

        if !models.contains(where: { $0.id == newChatFixedModelID }) {
            newChatFixedModelID = models.first?.id ?? newChatFixedModelID
        }
    }

    private func fixedMCPServerBinding(serverID: String) -> Binding<Bool> {
        Binding(
            get: {
                let current = Set(AppPreferences.decodeStringArrayJSON(newChatFixedMCPServerIDsJSON))
                return current.contains(serverID)
            },
            set: { isOn in
                var current = Set(AppPreferences.decodeStringArrayJSON(newChatFixedMCPServerIDsJSON))
                if isOn {
                    current.insert(serverID)
                } else {
                    current.remove(serverID)
                }
                newChatFixedMCPServerIDsJSON = AppPreferences.encodeStringArrayJSON(Array(current).sorted())
            }
        )
    }

    private func deleteAllChats() {
        for conversation in conversations {
            modelContext.delete(conversation)
        }
    }
}
