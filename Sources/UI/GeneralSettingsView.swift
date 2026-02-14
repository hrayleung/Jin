import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
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

                Button {
                    openDataDirectory()
                } label: {
                    Label("Open Data Directory", systemImage: "folder")
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

    private func normalizeTypographyPreferences() {
        appFontFamily = JinTypography.normalizedFontPreference(appFontFamily)
        codeFontFamily = JinTypography.normalizedFontPreference(codeFontFamily)
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

    private func openDataDirectory() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        let jinDir = appSupport.appendingPathComponent("Jin", isDirectory: true)

        if FileManager.default.fileExists(atPath: jinDir.path) {
            NSWorkspace.shared.open(jinDir)
        } else {
            NSWorkspace.shared.open(appSupport)
        }
    }
}

struct HideWindowToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WindowToolbarHider())
    }

    private struct WindowToolbarHider: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = ToolbarObservingView()
            return view
        }
        func updateNSView(_ nsView: NSView, context: Context) {
            (nsView as? ToolbarObservingView)?.hideToolbar()
        }
    }

    private final class ToolbarObservingView: NSView {
        private var windowObservation: NSKeyValueObservation?
        private var toolbarObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideToolbar()

            // Observe in case NavigationSplitView re-creates the toolbar
            windowObservation = observe(\.window?.toolbar, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.hideToolbar()
                }
            }
        }

        func hideToolbar() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            if let toolbar = window.toolbar {
                toolbar.isVisible = false
            }
        }
    }
}
