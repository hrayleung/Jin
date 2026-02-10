import SwiftUI
import SwiftData
import Combine
#if os(macOS)
import AppKit
#endif

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

    private struct GeneralSidebarHint: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let systemImage: String
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
        ),
        PluginDescriptor(
            id: "chat_naming",
            name: "Chat Naming",
            systemImage: "text.bubble",
            summary: "Name chats automatically via a selected model."
        )
    ]

    private static let generalSidebarHints: [GeneralSidebarHint] = [
        GeneralSidebarHint(
            title: "Appearance",
            subtitle: "Theme, font family, code font, and chat text size.",
            systemImage: "textformat"
        ),
        GeneralSidebarHint(
            title: "Model defaults",
            subtitle: "Control provider/model used by new chats.",
            systemImage: "sparkles"
        ),
        GeneralSidebarHint(
            title: "MCP defaults",
            subtitle: "Set MCP behavior for newly created chats.",
            systemImage: "server.rack"
        ),
        GeneralSidebarHint(
            title: "Local data",
            subtitle: "Inspect and manage on-device chat data.",
            systemImage: "externaldrive"
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
    @State private var pluginEnabledByID: [String: Bool] = [:]

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
                || server.transportSummary.localizedCaseInsensitiveContains(needle)
                || server.transportKind.rawValue.localizedCaseInsensitiveContains(needle)
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
            .scrollContentBackground(.hidden)
            .background {
                JinSemanticColor.sidebarSurface
                    .ignoresSafeArea()
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(JinSemanticColor.separator.opacity(0.45))
                    .frame(width: JinStrokeWidth.hairline)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
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
                    generalContextList
                }
            }
            .background {
                JinSemanticColor.panelSurface
                    .ignoresSafeArea()
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(JinSemanticColor.separator.opacity(0.4))
                    .frame(width: JinStrokeWidth.hairline)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)

        } detail: {
            // Column 3: Configuration / Detail
            Group {
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
                    } else if selectedPluginID == "chat_naming" {
                        ChatNamingPluginSettingsView()
                            .id("chat_naming")
                    } else {
                        ContentUnavailableView("Select a Plugin", systemImage: "puzzlepiece.extension")
                    }
                case .general, .none:
                    GeneralSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .toolbarBackground(JinSemanticColor.detailSurface, for: .windowToolbar)
            .navigationSplitViewColumnWidth(min: 500, ideal: 640)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 620)
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
        let defaults = UserDefaults.standard
        let pluginEnabled = Dictionary(uniqueKeysWithValues: Self.availablePlugins.map { plugin in
            (plugin.id, AppPreferences.isPluginEnabled(plugin.id, defaults: defaults))
        })

        await MainActor.run {
            pluginEnabledByID = pluginEnabled
        }
    }

    // MARK: - Providers List
    private var providersList: some View {
        List(filteredProviders, selection: $selectedProviderID) { provider in
            NavigationLink(value: provider.id) {
                HStack(spacing: JinSpacing.small + 2) {
                    ProviderIconView(iconID: provider.resolvedProviderIconID, fallbackSystemName: "network", size: 14)
                        .frame(width: 20, height: 20)
                        .jinSurface(.subtle, cornerRadius: JinRadius.small)

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
                .padding(.vertical, JinSpacing.xSmall)
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
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
        .onDeleteCommand {
            requestDeleteSelectedProvider()
        }
        .overlay {
            if !trimmedSearchText.isEmpty, filteredProviders.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
    }

    private var generalContextList: some View {
        List(Self.generalSidebarHints) { hint in
            HStack(spacing: JinSpacing.small + 2) {
                Image(systemName: hint.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hint.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(hint.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, JinSpacing.xSmall)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
    }

    // MARK: - Plugins List
    private var pluginsList: some View {
        List(filteredPlugins, selection: $selectedPluginID) { plugin in
            HStack(spacing: JinSpacing.small + 2) {
                Image(systemName: plugin.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .jinSurface(.subtle, cornerRadius: JinRadius.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(plugin.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: JinSpacing.small)

                Toggle("", isOn: pluginEnabledBinding(for: plugin.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .frame(width: 38, alignment: .trailing)
                    .help(isPluginEnabled(plugin.id) ? "Disable plugin" : "Enable plugin")
            }
            .padding(.vertical, JinSpacing.xSmall)
            .contentShape(Rectangle())
            .help(plugin.summary)
            .onTapGesture {
                selectedPluginID = plugin.id
            }
            .tag(plugin.id)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
        .overlay {
            if !trimmedSearchText.isEmpty, filteredPlugins.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
            }
        }
    }

    private func isPluginEnabled(_ pluginID: String) -> Bool {
        if let cached = pluginEnabledByID[pluginID] {
            return cached
        }
        return AppPreferences.isPluginEnabled(pluginID)
    }

    private func pluginEnabledBinding(for pluginID: String) -> Binding<Bool> {
        Binding(
            get: { isPluginEnabled(pluginID) },
            set: { isEnabled in
                AppPreferences.setPluginEnabled(isEnabled, for: pluginID)
                pluginEnabledByID[pluginID] = isEnabled
                NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
            }
        )
    }

    private var providersListWithActions: some View {
        VStack(spacing: 0) {
            providersList

            Divider()

            settingsActionBar {
                Button {
                    showingAddProvider = true
                } label: {
                    Label("Add Provider", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer(minLength: JinSpacing.small)

                Button(role: .destructive) {
                    requestDeleteSelectedProvider()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(selectedProviderID == nil)
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }

    // MARK: - MCP Servers List
    private var mcpServersList: some View {
        List(filteredMCPServers, selection: $selectedServerID) { server in
            NavigationLink(value: server.id) {
                HStack(spacing: JinSpacing.small + 2) {
                    Circle()
                        .fill(server.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                        Text(server.transportSummary)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(server.transportKind == .http ? "HTTP" : "STDIO")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .jinSurface(.subtle, cornerRadius: JinRadius.small)
                }
                .padding(.vertical, JinSpacing.xSmall)
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
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
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

            settingsActionBar {
                Button {
                    showingAddServer = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer(minLength: JinSpacing.small)

                Button(role: .destructive) {
                    requestDeleteSelectedServer()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(selectedServerID == nil)
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }

    private func settingsActionBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: JinSpacing.small) {
            content()
        }
        .padding(JinSpacing.medium)
        .background(JinSemanticColor.panelSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.45))
                .frame(height: JinStrokeWidth.hairline)
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

                switch providerType {
                case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .xai, .deepseek, .fireworks, .cerebras, .gemini:
                    SecureField("API Key", text: $apiKey)
                case .vertexai:
                    TextEditor(text: $serviceAccountJSON)
                        .frame(minHeight: 100)
                        .font(.system(.body, design: .monospaced))
                        .padding(JinSpacing.small)
                        .jinSurface(.raised, cornerRadius: JinRadius.small)
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
                    apiKey: providerType == .vertexai ? nil : trimmedAPIKey,
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
        case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .xai, .deepseek, .fireworks, .cerebras, .gemini:
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
    @State private var bearerToken = ""
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
                                .padding(JinSpacing.small)
                                .jinSurface(.raised, cornerRadius: JinRadius.small)
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
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                    .padding(JinSpacing.small)
                                    .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                            } else {
                                Text("Supports Claude Desktop-style configs (`mcpServers`) plus single-server payloads. HTTP imports are mapped to native HTTP transport.")
                                    .jinInfoCallout()
                            }
                        }
                        .padding(.top, 4)
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

                        SecureField("Bearer token", text: $bearerToken)
                            .font(.system(.body, design: .monospaced))

                        Toggle("Enable streaming (SSE)", isOn: $httpStreaming)
                    }

                    Section("Headers") {
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
            return parsedEndpoint == nil
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
            bearerToken = ""
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
            bearerToken = http.bearerToken ?? ""
            headerPairs = http.headers.map { EnvironmentVariablePair(key: $0.name, value: $0.value) }
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

            let headers: [MCPHeader] = headerPairs.compactMap { pair in
                let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return nil }
                return MCPHeader(
                    name: key,
                    value: pair.value,
                    isSensitive: Self.isSensitiveHeaderName(key)
                )
            }

            let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            transport = .http(
                MCPHTTPTransportConfig(
                    endpoint: endpointURL,
                    streaming: httpStreaming,
                    headers: headers,
                    bearerToken: token.isEmpty ? nil : token
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

    private static func isSensitiveHeaderName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["authorization", "proxy-authorization", "x-api-key", "api-key"].contains(normalized)
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


struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [ConversationEntity]
    @Query(sort: \ProviderConfigEntity.name) private var providers: [ProviderConfigEntity]
    @Query(sort: \MCPServerConfigEntity.name) private var mcpServers: [MCPServerConfigEntity]

    @State private var showingDeleteAllChatsConfirmation = false
    @State private var showingAppFontPicker = false
    @State private var showingCodeFontPicker = false

    @AppStorage(AppPreferenceKeys.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.chatMessageFontScale) private var chatMessageFontScale = JinTypography.defaultChatMessageScale

    @AppStorage(AppPreferenceKeys.newChatModelMode) private var newChatModelMode: NewChatModelMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedProviderID) private var newChatFixedProviderID = "openai"
    @AppStorage(AppPreferenceKeys.newChatFixedModelID) private var newChatFixedModelID = "gpt-5.2"
    @AppStorage(AppPreferenceKeys.newChatMCPMode) private var newChatMCPMode: NewChatMCPMode = .lastUsed
    @AppStorage(AppPreferenceKeys.newChatFixedMCPEnabled) private var newChatFixedMCPEnabled = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPUseAllServers) private var newChatFixedMCPUseAllServers = true
    @AppStorage(AppPreferenceKeys.newChatFixedMCPServerIDsJSON) private var newChatFixedMCPServerIDsJSON = "[]"
    @AppStorage(AppPreferenceKeys.allowAutomaticNetworkRequests) private var allowAutomaticNetworkRequests = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                LabeledContent("App Font") {
                    Button(appFontDisplayName) {
                        showingAppFontPicker = true
                    }
                    .buttonStyle(.borderless)
                }

                LabeledContent("Code Font") {
                    Button(codeFontDisplayName) {
                        showingCodeFontPicker = true
                    }
                    .buttonStyle(.borderless)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Chat Text Size")
                        Spacer()
                        Text(chatMessageScalePercentLabel)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: chatMessageFontScaleBinding,
                        in: JinTypography.chatMessageScaleRange,
                        step: JinTypography.chatMessageScaleStep
                    )

                    HStack(spacing: 10) {
                        Text("Applies to user and assistant message text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Button("Reset") {
                            chatMessageFontScale = JinTypography.defaultChatMessageScale
                        }
                        .disabled(abs(chatMessageFontScaleBinding.wrappedValue - JinTypography.defaultChatMessageScale) < 0.001)
                    }
                }
                .padding(.vertical, 4)
            }

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
                            .jinInfoCallout()
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
                        .jinInfoCallout()
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
                                    .jinInfoCallout()
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
                        .jinInfoCallout()
                }
            }

            Section("Network") {
                Toggle("Allow automatic network requests", isOn: $allowAutomaticNetworkRequests)

                Text("When off, Jin only makes network requests from explicit actions (e.g. Send, Fetch Models, Test Connection).")
                    .jinInfoCallout()
            }

            Section("Data") {
                Text("These actions affect local data stored on this Mac.")
                    .jinInfoCallout()

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
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .sheet(isPresented: $showingAppFontPicker) {
            FontPickerSheet(
                title: "App Font",
                subtitle: "Pick the default typeface used across the app.",
                selectedFontFamily: $appFontFamily
            )
        }
        .sheet(isPresented: $showingCodeFontPicker) {
            FontPickerSheet(
                title: "Code Font",
                subtitle: "Used for markdown code blocks in chat.",
                selectedFontFamily: $codeFontFamily
            )
        }
        .onAppear {
            ensureValidFixedModelSelection()
            normalizeTypographyPreferences()
        }
        .confirmationDialog("Delete all chats?", isPresented: $showingDeleteAllChatsConfirmation) {
            Button("Delete All Chats", role: .destructive) {
                deleteAllChats()
            }
        } message: {
            Text("This will permanently delete all chats across all assistants.")
        }
    }

    private var appFontDisplayName: String {
        JinTypography.displayName(for: appFontFamily)
    }

    private var codeFontDisplayName: String {
        JinTypography.displayName(for: codeFontFamily)
    }

    private var chatMessageFontScaleBinding: Binding<Double> {
        Binding(
            get: {
                JinTypography.clampedChatMessageScale(chatMessageFontScale)
            },
            set: { newValue in
                chatMessageFontScale = JinTypography.clampedChatMessageScale(newValue)
            }
        )
    }

    private var chatMessageScalePercentLabel: String {
        let clamped = JinTypography.clampedChatMessageScale(chatMessageFontScale)
        let percent = Int((clamped * 100).rounded())
        return "\(percent)%"
    }

    private func normalizeTypographyPreferences() {
        appFontFamily = JinTypography.normalizedFontPreference(appFontFamily)
        codeFontFamily = JinTypography.normalizedFontPreference(codeFontFamily)
        chatMessageFontScale = JinTypography.clampedChatMessageScale(chatMessageFontScale)
    }

    private var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func modelsForProvider(_ providerID: String) -> [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return []
        }
        return provider.enabledModels
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
