import SwiftUI
import SwiftData
import Combine
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query var conversations: [ConversationEntity]

    enum SettingsSection: String, CaseIterable, Identifiable {
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

    struct PluginDescriptor: Identifiable, Hashable {
        let id: String
        let name: String
        let systemImage: String
        let summary: String
    }

    static let availablePlugins: [PluginDescriptor] = [
        PluginDescriptor(id: "web_search_builtin", name: "Web Search", systemImage: "globe", summary: "Use Exa/Brave/Jina/Firecrawl as built-in search tools."),
        PluginDescriptor(id: "text_to_speech", name: "Text to Speech", systemImage: "speaker.wave.2", summary: "Play assistant replies aloud."),
        PluginDescriptor(id: "speech_to_text", name: "Speech to Text", systemImage: "mic", summary: "Dictate messages by voice."),
        PluginDescriptor(id: "mistral_ocr", name: "Mistral OCR", systemImage: "doc.text.magnifyingglass", summary: "OCR PDFs when native PDF isn't available."),
        PluginDescriptor(id: "mineru_ocr", name: "MinerU OCR", systemImage: "doc.text.magnifyingglass", summary: "OCR PDFs through MinerU Precision Extract."),
        PluginDescriptor(id: "deepseek_ocr", name: "DeepSeek OCR", systemImage: "doc.text.magnifyingglass", summary: "OCR PDFs using DeepInfra-hosted DeepSeek."),
        PluginDescriptor(id: "openrouter_ocr", name: "OpenRouter OCR", systemImage: "doc.text.magnifyingglass", summary: "OCR PDFs using curated OpenRouter OCR and document vision models."),
        PluginDescriptor(id: "firecrawl_ocr", name: "Firecrawl OCR", systemImage: "doc.text.magnifyingglass", summary: "OCR PDFs via Firecrawl after temporary Cloudflare R2 upload."),
        PluginDescriptor(id: "chat_naming", name: "Chat Naming", systemImage: "text.bubble", summary: "Auto-name chats with a selected model."),
        PluginDescriptor(id: "cloudflare_r2_upload", name: "Cloudflare R2 Upload", systemImage: "externaldrive.badge.icloud", summary: "Upload local videos to R2 for remote video URLs."),
        PluginDescriptor(id: "agent_mode", name: "Agent Mode", systemImage: "terminal", summary: "Execute local tools through the bundled RTK helper and local file operations.")
    ]

    @State var columnVisibility: NavigationSplitViewVisibility = .all
    @State var selectedSection: SettingsSection? = .providers
    @State var selectedProviderID: String?
    @State var selectedServerID: String?
    @State var selectedPluginID: String?
    @State var selectedGeneralCategory: GeneralSettingsCategory?
    @State var searchText = ""
    @State var providerPendingDeletion: ProviderConfigEntity?
    @State var showingDeleteProviderConfirmation = false
    @State var serverPendingDeletion: MCPServerConfigEntity?
    @State var showingDeleteServerConfirmation = false
    @State var operationErrorMessage: String?
    @State var showingOperationError = false
    @State var pluginEnabledByID: [String: Bool] = [:]

    @Query(sort: \ProviderConfigEntity.name) var providers: [ProviderConfigEntity]
    @Query(sort: \MCPServerConfigEntity.name) var mcpServers: [MCPServerConfigEntity]

    @State var showingAddProvider = false
    @State var showingAddServer = false

    // MARK: - Computed Filters

    var trimmedSearchText: String {
        SettingsSearchSupport.trimmedSearchText(searchText)
    }

    var filteredProviders: [ProviderConfigEntity] {
        SettingsSearchSupport.filteredProviders(providers, searchText: searchText)
    }

    var filteredMCPServers: [MCPServerConfigEntity] {
        SettingsSearchSupport.filteredMCPServers(mcpServers, searchText: searchText)
    }

    var filteredPlugins: [PluginDescriptor] {
        SettingsSearchSupport.filteredPlugins(Self.availablePlugins, searchText: searchText)
    }

    // MARK: - Animation Helpers

    var settingsMotionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    var pluginSelectionAnimation: Animation? {
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

    func animatedBinding<T>(_ value: Binding<T>) -> Binding<T> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                withAnimation(settingsMotionAnimation) {
                    value.wrappedValue = newValue
                }
            }
        )
    }

    var animatedSelectedSection: Binding<SettingsSection?> { animatedBinding($selectedSection) }
    var animatedSelectedProviderID: Binding<String?> { animatedBinding($selectedProviderID) }
    var animatedSelectedServerID: Binding<String?> { animatedBinding($selectedServerID) }
    var animatedSelectedPluginID: Binding<String?> { animatedBinding($selectedPluginID) }
    var animatedSelectedGeneralCategory: Binding<GeneralSettingsCategory?> { animatedBinding($selectedGeneralCategory) }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("")
        .toolbar(removing: .sidebarToggle)
        .hideWindowToolbarCompat()
        .frame(minWidth: 1_060, idealWidth: 1_140, minHeight: 620, idealHeight: 700)
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView()
        }
        .sheet(isPresented: $showingAddServer) {
            AddMCPServerView()
        }
        .onAppear { ensureValidSelection() }
        .onChange(of: searchText) { _, _ in ensureValidSelection() }
        .onChange(of: selectedSection) { _, _ in ensureValidSelection() }
        .onChange(of: providers.count) { _, _ in ensureValidSelection() }
        .onChange(of: mcpServers.count) { _, _ in ensureValidSelection() }
        .alert("Couldn't update settings", isPresented: $showingOperationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationErrorMessage ?? "Please try again.")
        }
        .task { await refreshPluginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .pluginCredentialsDidChange)) { _ in
            Task { await refreshPluginStatus() }
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: .settingsNavigateToPlugin)
                .receive(on: RunLoop.main)
        ) { notification in
            guard
                let pluginID = notification.userInfo?[SettingsNavigationUserInfoKey.pluginID] as? String,
                Self.availablePlugins.contains(where: { $0.id == pluginID })
            else { return }
            withAnimation(settingsMotionAnimation) {
                selectedSection = .plugins
                selectedPluginID = pluginID
            }
        }
        .confirmationDialog(
            "Delete provider?",
            isPresented: $showingDeleteProviderConfirmation,
            presenting: providerPendingDeletion
        ) { provider in
            Button("Delete", role: .destructive) { deleteProvider(provider) }
        } message: { provider in
            Text(providerDeletionMessage(provider))
        }
        .confirmationDialog(
            "Delete MCP server?",
            isPresented: $showingDeleteServerConfirmation,
            presenting: serverPendingDeletion
        ) { server in
            Button("Delete", role: .destructive) { deleteServer(server) }
        } message: { server in
            Text(SettingsDeletionSupport.serverDeletionMessage(serverName: server.name))
        }
    }

    // MARK: - Columns

    private var sidebarColumn: some View {
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
        .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            switch selectedSection {
            case .providers:
                providersListWithActions.transition(settingsColumnTransition)
            case .mcpServers:
                mcpServersListWithActions.transition(settingsColumnTransition)
            case .plugins:
                pluginsList.transition(settingsColumnTransition)
            case .general, .none:
                generalCategoriesList.transition(settingsColumnTransition)
            }
        }
        .animation(settingsMotionAnimation, value: selectedSection)
        .background {
            JinSemanticColor.panelSurface.ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.4))
                .frame(width: JinStrokeWidth.hairline)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 230, max: 230)
    }

    private var detailColumn: some View {
        Group {
            switch selectedSection {
            case .providers:
                providerDetailView
            case .mcpServers:
                mcpServerDetailView
            case .plugins:
                pluginDetailView
            case .general, .none:
                generalDetailView
            }
        }
        .animation(settingsMotionAnimation, value: detailSelectionKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            JinSemanticColor.detailSurface.ignoresSafeArea()
        }
        .toolbarBackground(JinSemanticColor.detailSurface, for: .windowToolbar)
        .navigationSplitViewColumnWidth(min: 500, ideal: 620, max: 820)
    }

    // MARK: - Detail Sub-Views

    @ViewBuilder
    private var providerDetailView: some View {
        if let id = selectedProviderID, let provider = providers.first(where: { $0.id == id }) {
            identifiedDetail(id) {
                ProviderConfigFormView(provider: provider)
            }
        } else {
            transitionedDetail {
                ContentUnavailableView("Select a Provider", systemImage: "network")
            }
        }
    }

    @ViewBuilder
    private var mcpServerDetailView: some View {
        if let id = selectedServerID, let server = mcpServers.first(where: { $0.id == id }) {
            identifiedDetail(id) {
                MCPServerConfigFormView(server: server)
            }
        } else {
            transitionedDetail {
                ContentUnavailableView("Select an MCP server", systemImage: "server.rack")
            }
        }
    }

    @ViewBuilder
    private var pluginDetailView: some View {
        switch selectedPluginID {
        case "mistral_ocr":
            identifiedDetail("mistral_ocr") { MistralOCRPluginSettingsView() }
        case "mineru_ocr":
            identifiedDetail("mineru_ocr") { MinerUOCRPluginSettingsView() }
        case "web_search_builtin":
            identifiedDetail("web_search_builtin") { WebSearchPluginSettingsView() }
        case "deepseek_ocr":
            identifiedDetail("deepseek_ocr") { DeepSeekOCRPluginSettingsView() }
        case "openrouter_ocr":
            identifiedDetail("openrouter_ocr") { OpenRouterOCRPluginSettingsView() }
        case "firecrawl_ocr":
            identifiedDetail("firecrawl_ocr") { FirecrawlOCRPluginSettingsView() }
        case "text_to_speech":
            identifiedDetail("text_to_speech") { TextToSpeechPluginSettingsView() }
        case "speech_to_text":
            identifiedDetail("speech_to_text") { SpeechToTextPluginSettingsView() }
        case "chat_naming":
            identifiedDetail("chat_naming") { ChatNamingPluginSettingsView() }
        case "cloudflare_r2_upload":
            identifiedDetail("cloudflare_r2_upload") { CloudflareR2UploadPluginSettingsView() }
        case "agent_mode":
            identifiedDetail("agent_mode") { AgentModeSettingsView() }
        default:
            transitionedDetail {
                ContentUnavailableView("Select a Plugin", systemImage: "puzzlepiece.extension")
            }
        }
    }

    @ViewBuilder
    private var generalDetailView: some View {
        switch selectedGeneralCategory {
        case .appearance:
            identifiedDetail("appearance") { AppearanceSettingsView() }
        case .chat:
            identifiedDetail("chat") { ChatSettingsView() }
        case .shortcuts:
            identifiedDetail("shortcuts") { KeyboardShortcutsSettingsView() }
        case .defaults:
            identifiedDetail("defaults") { DefaultsSettingsView() }
        case .updates:
            identifiedDetail("updates") { UpdateSettingsView() }
        case .data:
            identifiedDetail("data") { DataSettingsView() }
        case nil:
            transitionedDetail {
                ContentUnavailableView("Select a Category", systemImage: "gearshape")
            }
        }
    }

    @ViewBuilder
    private func identifiedDetail<ID: Hashable, Content: View>(
        _ id: ID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .id(id)
            .transition(settingsColumnTransition)
    }

    @ViewBuilder
    private func transitionedDetail<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .transition(settingsColumnTransition)
    }
}
