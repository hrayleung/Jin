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
            subtitle: "Theme, font family, and code font.",
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

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
                    switch selectedPluginID {
                    case "mistral_ocr":
                        MistralOCRPluginSettingsView()
                            .id("mistral_ocr")
                    case "deepseek_ocr":
                        DeepSeekOCRPluginSettingsView()
                            .id("deepseek_ocr")
                    case "text_to_speech":
                        TextToSpeechPluginSettingsView()
                            .id("text_to_speech")
                    case "speech_to_text":
                        SpeechToTextPluginSettingsView()
                            .id("speech_to_text")
                    case "chat_naming":
                        ChatNamingPluginSettingsView()
                            .id("chat_naming")
                    default:
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
        .toolbar(removing: .sidebarToggle)
        .modifier(HideWindowToolbarModifier())
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

        // Clear unrelated selections for current section
        if selectedSection != .providers { selectedProviderID = nil }
        if selectedSection != .mcpServers { selectedServerID = nil }
        if selectedSection != .plugins { selectedPluginID = nil }

        switch selectedSection {
        case .providers:
            let candidates = filteredProviders
            if let selectedProviderID,
               candidates.contains(where: { $0.id == selectedProviderID }) {
                return
            }
            selectedProviderID = candidates.first?.id

        case .mcpServers:
            let candidates = filteredMCPServers
            if let selectedServerID,
               candidates.contains(where: { $0.id == selectedServerID }) {
                return
            }
            selectedServerID = candidates.first?.id

        case .plugins:
            let candidates = filteredPlugins
            if let selectedPluginID,
               candidates.contains(where: { $0.id == selectedPluginID }) {
                return
            }
            selectedPluginID = candidates.first?.id

        case .general, .none:
            if selectedSection == nil {
                selectedSection = .providers
            }
        }
    }
}
