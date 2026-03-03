import SwiftUI
import SwiftData
import Combine
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            id: "web_search_builtin",
            name: "Web Search",
            systemImage: "globe",
            summary: "Use Exa/Brave/Jina/Firecrawl as built-in search tools."
        ),
        PluginDescriptor(
            id: "text_to_speech",
            name: "Text to Speech",
            systemImage: "speaker.wave.2",
            summary: "Play assistant replies aloud."
        ),
        PluginDescriptor(
            id: "speech_to_text",
            name: "Speech to Text",
            systemImage: "mic",
            summary: "Dictate messages by voice."
        ),
        PluginDescriptor(
            id: "mistral_ocr",
            name: "Mistral OCR",
            systemImage: "doc.text.magnifyingglass",
            summary: "OCR PDFs when native PDF isn't available."
        ),
        PluginDescriptor(
            id: "deepseek_ocr",
            name: "DeepSeek OCR",
            systemImage: "doc.text.magnifyingglass",
            summary: "OCR PDFs using DeepInfra-hosted DeepSeek."
        ),
        PluginDescriptor(
            id: "chat_naming",
            name: "Chat Naming",
            systemImage: "text.bubble",
            summary: "Auto-name chats with a selected model."
        ),
        PluginDescriptor(
            id: "cloudflare_r2_upload",
            name: "Cloudflare R2 Upload",
            systemImage: "externaldrive.badge.icloud",
            summary: "Upload local videos to R2 for remote video URLs."
        )
    ]

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedSection: SettingsSection? = .providers
    @State private var selectedProviderID: String?
    @State private var selectedServerID: String?
    @State private var selectedPluginID: String?
    @State private var selectedGeneralCategory: GeneralSettingsCategory?
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

    private var settingsMotionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private var pluginSelectionAnimation: Animation? {
        settingsMotionAnimation
    }

    private var settingsColumnTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 4)),
            removal: .opacity.combined(with: .offset(y: -2))
        )
    }

    private var detailSelectionKey: String {
        switch selectedSection {
        case .providers:
            return "providers:\(selectedProviderID ?? "")"
        case .mcpServers:
            return "mcp:\(selectedServerID ?? "")"
        case .plugins:
            return "plugins:\(selectedPluginID ?? "")"
        case .general:
            return "general:\(selectedGeneralCategory?.rawValue ?? "")"
        case .none:
            return "none"
        }
    }

    /// Creates a Binding that wraps writes in the settings motion animation.
    private func animatedBinding<T>(_ value: Binding<T>) -> Binding<T> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                withAnimation(settingsMotionAnimation) {
                    value.wrappedValue = newValue
                }
            }
        )
    }

    private var animatedSelectedSection: Binding<SettingsSection?> {
        animatedBinding($selectedSection)
    }

    private var animatedSelectedProviderID: Binding<String?> {
        animatedBinding($selectedProviderID)
    }

    private var animatedSelectedServerID: Binding<String?> {
        animatedBinding($selectedServerID)
    }

    private var animatedSelectedPluginID: Binding<String?> {
        animatedBinding($selectedPluginID)
    }

    private var animatedSelectedGeneralCategory: Binding<GeneralSettingsCategory?> {
        animatedBinding($selectedGeneralCategory)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Column 1: Navigation Sidebar
            List(SettingsSection.allCases, selection: animatedSelectedSection) { section in
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
                        .transition(settingsColumnTransition)
                case .mcpServers:
                    mcpServersListWithActions
                        .transition(settingsColumnTransition)
                case .plugins:
                    pluginsList
                        .transition(settingsColumnTransition)
                case .general, .none:
                    generalCategoriesList
                        .transition(settingsColumnTransition)
                }
            }
            .animation(settingsMotionAnimation, value: selectedSection)
            .background {
                JinSemanticColor.panelSurface
                    .ignoresSafeArea()
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(JinSemanticColor.separator.opacity(0.4))
                    .frame(width: JinStrokeWidth.hairline)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 340)

        } detail: {
            // Column 3: Configuration / Detail
            Group {
                switch selectedSection {
                case .providers:
                    if let id = selectedProviderID, let provider = providers.first(where: { $0.id == id }) {
                        ProviderConfigFormView(provider: provider)
                            .id(id) // Force refresh
                            .transition(settingsColumnTransition)
                    } else {
                        ContentUnavailableView("Select a Provider", systemImage: "network")
                            .transition(settingsColumnTransition)
                    }
                case .mcpServers:
                    if let id = selectedServerID, let server = mcpServers.first(where: { $0.id == id }) {
                        MCPServerConfigFormView(server: server)
                            .id(id)
                            .transition(settingsColumnTransition)
                    } else {
                        ContentUnavailableView("Select an MCP Server", systemImage: "server.rack")
                            .transition(settingsColumnTransition)
                    }
                case .plugins:
                    switch selectedPluginID {
                    case "mistral_ocr":
                        MistralOCRPluginSettingsView()
                            .id("mistral_ocr")
                            .transition(settingsColumnTransition)
                    case "web_search_builtin":
                        WebSearchPluginSettingsView()
                            .id("web_search_builtin")
                            .transition(settingsColumnTransition)
                    case "deepseek_ocr":
                        DeepSeekOCRPluginSettingsView()
                            .id("deepseek_ocr")
                            .transition(settingsColumnTransition)
                    case "text_to_speech":
                        TextToSpeechPluginSettingsView()
                            .id("text_to_speech")
                            .transition(settingsColumnTransition)
                    case "speech_to_text":
                        SpeechToTextPluginSettingsView()
                            .id("speech_to_text")
                            .transition(settingsColumnTransition)
                    case "chat_naming":
                        ChatNamingPluginSettingsView()
                            .id("chat_naming")
                            .transition(settingsColumnTransition)
                    case "cloudflare_r2_upload":
                        CloudflareR2UploadPluginSettingsView()
                            .id("cloudflare_r2_upload")
                            .transition(settingsColumnTransition)
                    default:
                        ContentUnavailableView("Select a Plugin", systemImage: "puzzlepiece.extension")
                            .transition(settingsColumnTransition)
                    }
                case .general, .none:
                    switch selectedGeneralCategory {
                    case .appearance:
                        AppearanceSettingsView()
                            .id("appearance")
                            .transition(settingsColumnTransition)
                    case .chat:
                        ChatSettingsView()
                            .id("chat")
                            .transition(settingsColumnTransition)
                    case .shortcuts:
                        KeyboardShortcutsSettingsView()
                            .id("shortcuts")
                            .transition(settingsColumnTransition)
                    case .defaults:
                        DefaultsSettingsView()
                            .id("defaults")
                            .transition(settingsColumnTransition)
                    case .updates:
                        UpdateSettingsView()
                            .id("updates")
                            .transition(settingsColumnTransition)
                    case .data:
                        DataSettingsView()
                            .id("data")
                            .transition(settingsColumnTransition)
                    case nil:
                        ContentUnavailableView("Select a Category", systemImage: "gearshape")
                            .transition(settingsColumnTransition)
                    }
                }
            }
            .animation(settingsMotionAnimation, value: detailSelectionKey)
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
        .hideWindowToolbarCompat()
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
        List(filteredProviders, selection: animatedSelectedProviderID) { provider in
            NavigationLink(value: provider.id) {
                HStack(spacing: JinSpacing.small + 2) {
                    ProviderIconView(iconID: provider.resolvedProviderIconID, fallbackSystemName: "network", size: 14)
                        .frame(width: 20, height: 20)
                        .jinSurface(.outlined, cornerRadius: JinRadius.small)
                        .opacity(provider.isEnabled ? 1 : 0.4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                        Text(ProviderType(rawValue: provider.typeRaw)?.displayName ?? provider.typeRaw)
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.secondary)
                    }
                    .opacity(provider.isEnabled ? 1 : 0.4)

                    Spacer()
                }
                .padding(.vertical, JinSpacing.xSmall)
            }
            .contextMenu {
                Button {
                    provider.isEnabled.toggle()
                    try? modelContext.save()
                } label: {
                    Label(
                        provider.isEnabled ? "Disable Provider" : "Enable Provider",
                        systemImage: provider.isEnabled ? "xmark.circle" : "checkmark.circle"
                    )
                }

                Divider()

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

    private var generalCategoriesList: some View {
        List(GeneralSettingsCategory.allCases, selection: animatedSelectedGeneralCategory) { category in
            NavigationLink(value: category) {
                HStack(spacing: JinSpacing.small + 2) {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .jinSurface(.outlined, cornerRadius: JinRadius.small)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.label)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(category.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, JinSpacing.xSmall)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.panelSurface)
    }

    // MARK: - Plugins List
    private var pluginsList: some View {
        List(filteredPlugins, selection: animatedSelectedPluginID) { plugin in
            let isSelected = selectedPluginID == plugin.id

            HStack(spacing: JinSpacing.small + 2) {
                Image(systemName: plugin.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .jinSurface(.outlined, cornerRadius: JinRadius.small)

                Text(plugin.name)
                    .font(.system(.body, design: .default))
                    .fontWeight(.medium)
                    .lineLimit(isSelected ? nil : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: isSelected)
                    .layoutPriority(1)
                    .animation(pluginSelectionAnimation, value: isSelected)

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
            .onTapGesture {
                guard selectedPluginID != plugin.id else { return }
                animatedSelectedPluginID.wrappedValue = plugin.id
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
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Add Provider")
                .accessibilityLabel("Add Provider")

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
        List(filteredMCPServers, selection: animatedSelectedServerID) { server in
            NavigationLink(value: server.id) {
                HStack(spacing: JinSpacing.small + 2) {
                    ZStack(alignment: .bottomTrailing) {
                        MCPIconView(iconID: server.resolvedMCPIconID, fallbackSystemName: "server.rack", size: 14)
                            .frame(width: 20, height: 20)
                            .jinSurface(.subtle, cornerRadius: JinRadius.small)

                        Circle()
                            .fill(server.isEnabled ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .stroke(JinSemanticColor.panelSurface, lineWidth: 1)
                            )
                            .offset(x: 1, y: 1)
                    }
                    .frame(width: 24, height: 24)

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
                        .jinSurface(.outlined, cornerRadius: JinRadius.small)
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
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Add MCP Server")
                .accessibilityLabel("Add MCP Server")

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
        if selectedSection != .general { selectedGeneralCategory = nil }

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

        case .general:
            if selectedGeneralCategory == nil {
                selectedGeneralCategory = .appearance
            }

        case .none:
            selectedSection = .providers
        }
    }
}
