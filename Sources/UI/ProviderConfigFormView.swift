import SwiftUI
import SwiftData

struct ProviderConfigFormView: View {
    @Bindable var provider: ProviderConfigEntity
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @ObservedObject private var codexServerController = CodexAppServerController.shared
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""
    @State private var codexAuthMode: CodexAuthMode = .apiKey
    @State private var codexAuthStatus: CodexAuthStatus = .idle
    @State private var codexAccount: CodexAppServerAdapter.AccountStatus?
    @State private var codexRateLimit: CodexAppServerAdapter.RateLimitStatus?
    @State private var codexPendingLoginID: String?
    @State private var codexAuthTask: Task<Void, Never>?
    @State private var codexServerLaunchError: String?
    @State private var codexWorkingDirectoryPresets: [CodexWorkingDirectoryPreset] = []
    @State private var codexWorkingDirectoryPresetsDraft: [CodexWorkingDirectoryPreset] = []
    @State private var showingCodexWorkingDirectoryPresetsSheet = false
    @State private var showingAPIKey = false
    @State private var hasLoadedCredentials = false
    @State private var credentialSaveError: String?
    @State private var credentialSaveTask: Task<Void, Never>?
    @State private var testStatus: TestStatus = .idle
    @State private var isFetchingModels = false
    @State private var modelsError: String?
    @State private var showingAddModel = false
    @State private var showingDeleteAllModelsConfirmation = false
    @State private var showingDeleteModelConfirmation = false
    @State private var showingKeepFullySupportedModelsConfirmation = false
    @State private var showingKeepEnabledModelsConfirmation = false
    @State private var fetchedModelsForSelection: FetchedModelsSelectionState?
    @State private var modelSearchText = ""
    @State private var editingModel: ModelInfo?
    @State private var modelPendingDeletion: ModelInfo?
    @State private var hoveredModelID: String?
    @State private var openRouterUsageStatus: OpenRouterUsageStatus = .idle
    @State private var openRouterUsage: OpenRouterKeyUsage?
    @State private var openRouterUsageTask: Task<Void, Never>?

    private let providerManager = ProviderManager()
    private let networkManager = NetworkManager()

    private struct FetchedModelsSelectionState: Identifiable {
        let id = UUID()
        let models: [ModelInfo]
    }

    var body: some View {
        Form {
            Section("Configuration") {
                Toggle(isOn: Binding(
                    get: { provider.isEnabled },
                    set: { newValue in
                        provider.isEnabled = newValue
                        try? modelContext.save()
                    }
                )) {
                    Text("Enabled")
                }

                TextField("Name", text: $provider.name)
                    .onChange(of: provider.name) { _, _ in try? modelContext.save() }

                ProviderIconPickerField(
                    selectedIconID: Binding(
                        get: { provider.iconID },
                        set: { newValue in
                            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                            provider.iconID = trimmed?.isEmpty == false ? trimmed : nil
                            try? modelContext.save()
                        }
                    ),
                    defaultIconID: providerType.map { LobeProviderIconCatalog.defaultIconID(for: $0) }
                )

                if let providerType, let defaultBaseURL = providerType.defaultBaseURL {
                    HStack {
                        TextField("Base URL", text: baseURLBinding(defaultBaseURL: defaultBaseURL))
                        Button("Reset") {
                            provider.baseURL = defaultBaseURL
                        }
                        .disabled((provider.baseURL ?? defaultBaseURL) == defaultBaseURL)
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    if providerType == .cerebras {
                        let base = (provider.baseURL ?? defaultBaseURL).lowercased()
                        if base.contains("cerebras-sandbox.net") {
                            Text("Warning: cerebras-sandbox.net is the web sandbox and is Cloudflare-protected. Use the API endpoint https://api.cerebras.ai/v1 instead.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                }

                switch providerType {
                case .codexAppServer:
                    codexOverviewSection
                    codexServerSection
                    codexAuthSection
                    codexWorkingDirectoryPresetsSection
                case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
                     .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai,
                     .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini:
                    apiKeyField
                case .vertexai:
                    vertexAISection
                case .none:
                    Text("Unknown provider type")
                        .foregroundColor(.secondary)
                }

                if providerType == .openrouter {
                    openRouterUsageSection
                }

                if let credentialSaveError {
                    Text(credentialSaveError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                testConnectionButton
            }

            Section("Models") {
                if let modelsError {
                    Text(modelsError)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                if !decodedModels.isEmpty {
                    TextField("Search models", text: $modelSearchText)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: JinSpacing.small) {
                        Text("Enabled \(enabledModelCount) / \(decodedModels.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Enable All") {
                            setAllModelsEnabled(true)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Divider().frame(height: 12)

                        Button("Disable All") {
                            setAllModelsEnabled(false)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Divider().frame(height: 12)

                        Menu {
                            Button {
                                showingKeepFullySupportedModelsConfirmation = true
                            } label: {
                                Label("Keep Fully Supported", systemImage: "checkmark.seal")
                            }
                            .disabled(!canKeepFullySupportedModels)

                            Button {
                                showingKeepEnabledModelsConfirmation = true
                            } label: {
                                Label("Keep Enabled Only", systemImage: "power")
                            }
                            .disabled(!canKeepEnabledModels)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 22)
                        .help("Filter actions")
                        .accessibilityLabel("Filter actions")
                    }
                }

                if decodedModels.isEmpty {
                    Text("No models found. Fetch from provider or add manually.")
                        .jinInfoCallout()
                } else if filteredModels.isEmpty {
                    Text("No models match your search.")
                        .jinInfoCallout()
                } else {
                    List(filteredModels) { model in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(model.name)
                                        .lineLimit(1)

                                    if isFullySupportedModel(model.id) {
                                        Text(JinModelSupport.fullSupportSymbol)
                                            .jinTagStyle(foreground: .green)
                                            .help("Jin full support")
                                    }

                                    if model.overrides != nil {
                                        Text("Custom")
                                            .jinTagStyle(foreground: .orange)
                                            .help("This model has manual capability overrides.")
                                    }
                                }

                                Text(model.id)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }

                            Spacer(minLength: 8)

                            Button {
                                editingModel = model
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Model Settings")
                            .opacity(hoveredModelID == model.id ? 1 : 0)

                            Button(role: .destructive) {
                                requestDeleteModel(model)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Delete Model")
                            .opacity(hoveredModelID == model.id ? 1 : 0)

                            Toggle("", isOn: modelEnabledBinding(modelID: model.id))
                                .labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingModel = model
                        }
                        .onHover { isHovered in
                            if isHovered {
                                hoveredModelID = model.id
                            } else if hoveredModelID == model.id {
                                hoveredModelID = nil
                            }
                        }
                    }
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .background(JinSemanticColor.detailSurface)
                    .jinSurface(.outlined, cornerRadius: JinRadius.medium)
                }

                HStack {
                    Button("Fetch from Provider") {
                        Task { await fetchModels() }
                    }
                    .disabled(isFetchModelsDisabled)

                    if isFetchingModels {
                        ProgressView().scaleEffect(0.5)
                    }

                    Spacer()

                    Button {
                        showingAddModel = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        showingDeleteAllModelsConfirmation = true
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(decodedModels.isEmpty)
                    .buttonStyle(.borderless)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: filteredModels.count)
            .animation(.easeInOut(duration: 0.18), value: modelSearchText)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .task {
            await loadCredentials()
            await MainActor.run {
                if providerType == .codexAppServer {
                    loadCodexWorkingDirectoryPresets()
                    codexServerController.refreshManagedProcesses()
                } else {
                    codexWorkingDirectoryPresets = []
                }
                hasLoadedCredentials = true
            }
            if providerType == .openrouter {
                await refreshOpenRouterUsage(force: true)
            }
            if providerType == .codexAppServer, codexAuthMode == .chatGPT {
                await refreshCodexAccountStatus(forceRefreshToken: false)
            }
        }
        .onChange(of: apiKey) { _, _ in
            guard hasLoadedCredentials else { return }
            scheduleCredentialSave()
            if providerType == .openrouter {
                scheduleOpenRouterUsageRefresh()
            }
        }
        .onChange(of: codexAuthMode) { _, _ in
            guard hasLoadedCredentials else { return }
            codexAuthTask?.cancel()
            codexPendingLoginID = nil
            codexAccount = nil
            codexRateLimit = nil
            codexAuthStatus = .idle
            scheduleCredentialSave()
            if codexAuthMode == .chatGPT {
                Task { await refreshCodexAccountStatus(forceRefreshToken: false) }
            }
        }
        .onChange(of: serviceAccountJSON) { _, _ in
            guard hasLoadedCredentials else { return }
            scheduleCredentialSave()
        }
        .onDisappear {
            credentialSaveTask?.cancel()
            openRouterUsageTask?.cancel()
            codexAuthTask?.cancel()
        }
        .sheet(isPresented: $showingCodexWorkingDirectoryPresetsSheet) {
            CodexWorkingDirectoryPresetsManagerSheetView(
                presets: $codexWorkingDirectoryPresetsDraft,
                onCancel: { showingCodexWorkingDirectoryPresetsSheet = false },
                onSave: {
                    codexWorkingDirectoryPresets = codexWorkingDirectoryPresetsDraft
                    persistCodexWorkingDirectoryPresets()
                    showingCodexWorkingDirectoryPresetsSheet = false
                }
            )
        }
        .sheet(item: $fetchedModelsForSelection) { selection in
            FetchedModelsSelectionSheet(
                fetchedModels: selection.models,
                existingModelIDs: Set(decodedModels.map(\.id)),
                providerType: providerType,
                onConfirm: { selectedModels in
                    let merged = addSelectedAndRefreshExisting(
                        selected: selectedModels,
                        allFetched: selection.models
                    )
                    setModels(merged)
                }
            )
        }
        .sheet(isPresented: $showingAddModel) {
                AddModelSheet(
                    providerType: providerType,
                    onAdd: { model in
                        var models = decodedModels
                        if let existingIndex = models.firstIndex(where: { $0.id == model.id }) {
                            models[existingIndex] = model
                        } else {
                            models.append(model)
                        }
                        models.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                        setModels(models)
                    }
                )
        }
        .sheet(item: $editingModel) { model in
            ModelSettingsSheet(
                model: model,
                providerType: providerType,
                onSave: { updated in
                    updateModel(updated)
                }
            )
        }
        .confirmationDialog(
            "Delete all models for \(provider.name)?",
            isPresented: $showingDeleteAllModelsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                setModels([])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the local model list. You can fetch it again anytime.")
        }
        .confirmationDialog(
            "Keep fully supported models for \(provider.name)?",
            isPresented: $showingKeepFullySupportedModelsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Fully Supported", role: .destructive) {
                keepOnlyFullySupportedModels()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete \(nonFullySupportedModelsCount) models not marked as fully supported and keep \(fullySupportedModelsCount) fully supported model(s).")
        }
        .confirmationDialog(
            "Keep enabled models for \(provider.name)?",
            isPresented: $showingKeepEnabledModelsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Enabled", role: .destructive) {
                keepOnlyEnabledModels()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete \(disabledModelCount) disabled model(s) and keep \(enabledModelCount) enabled model(s).")
        }
        .confirmationDialog(
            "Delete model for \(provider.name)?",
            isPresented: $showingDeleteModelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let modelPendingDeletion {
                    deleteModel(modelPendingDeletion)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let modelPendingDeletion {
                Text("This will delete the model “\(modelPendingDeletion.name)” (\(modelPendingDeletion.id)).")
            } else {
                Text("This will remove this model from the local model list.")
            }
        }
    }

    private var providerType: ProviderType? {
        ProviderType(rawValue: provider.typeRaw)
    }

    private func isFullySupportedModel(_ modelID: String) -> Bool {
        guard let providerType else { return false }
        return JinModelSupport.isFullySupported(providerType: providerType, modelID: modelID)
    }

    private func baseURLBinding(defaultBaseURL: String) -> Binding<String> {
        Binding(
            get: { provider.baseURL ?? defaultBaseURL },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    provider.baseURL = defaultBaseURL
                } else {
                    provider.baseURL = trimmed
                }
                try? modelContext.save()
            }
        )
    }

    // MARK: - API Key Section

    private var apiKeyField: some View {
        HStack(spacing: 8) {
            Group {
                if showingAPIKey {
                    TextField(apiKeyFieldTitle, text: $apiKey)
                } else {
                    SecureField(apiKeyFieldTitle, text: $apiKey)
                }
            }
            Button {
                showingAPIKey.toggle()
            } label: {
                Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(showingAPIKey ? "Hide API key" : "Show API key")
            .disabled(apiKey.isEmpty)
        }
    }

    private var apiKeyFieldTitle: String {
        providerType == .githubCopilot ? "GitHub Token" : "API Key"
    }

    // MARK: - Codex Auth

    private var codexOverviewSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Jin talks to Codex App Server over WebSocket. Use this screen for provider-level setup, then tune per-chat sandbox, personality, and working directory from the chat toolbar.")
                .jinInfoCallout()
        }
        .padding(.vertical, 4)
    }

    private var codexServerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(codexServerStatusColor)
                    .frame(width: 8, height: 8)
                Text(codexServerStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(codexServerStatusMessage)
                .foregroundStyle(.secondary)

            if let codexServerLaunchError {
                Text(codexServerLaunchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let lastLine = codexServerController.lastOutputLine, !lastLine.isEmpty {
                Text(lastLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if codexServerController.managedProcessCount > 0,
               case .stopped = codexServerController.status {
                Text("Detected \(codexServerController.managedProcessCount) Jin-managed Codex app-server process(es) still running. Use Force Stop to clean them up.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button {
                    startCodexServer()
                } label: {
                    Label("Start Server", systemImage: "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(codexServerStartDisabled)

                Button {
                    stopCodexServer()
                } label: {
                    Label("Stop Server", systemImage: "stop.fill")
                }
                .buttonStyle(.borderless)
                .disabled(codexServerStopDisabled)

                Button(role: .destructive) {
                    forceStopCodexServer()
                } label: {
                    Label("Force Stop", systemImage: "bolt.slash.fill")
                }
                .buttonStyle(.borderless)
                .disabled(codexServerForceStopDisabled)

                Button {
                    codexServerController.refreshManagedProcesses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Jin-managed Codex process status")
            }
        }
        .padding(.vertical, 4)
    }

    private var codexServerStatusLabel: String {
        switch codexServerController.status {
        case .stopped:
            return "Server stopped"
        case .starting:
            return "Server starting"
        case .running:
            return "Server running"
        case .stopping:
            return "Server stopping"
        case .failed:
            return "Server failed"
        }
    }

    private var codexServerStatusColor: Color {
        switch codexServerController.status {
        case .running:
            return .green
        case .starting, .stopping:
            return .orange
        case .stopped:
            return .secondary
        case .failed:
            return .red
        }
    }

    private var codexServerStatusMessage: String {
        if let validation = codexServerListenURLValidationError {
            return validation
        }

        switch codexServerController.status {
        case .running(let pid, let listenURL):
            return "`codex app-server` is running (pid \(pid)) on \(listenURL)"
        case .starting:
            return "Starting `codex app-server --listen \(codexServerListenURL)`..."
        case .stopping:
            return "Stopping `codex app-server`..."
        case .failed(let message):
            return message
        case .stopped:
            return "Ready to launch `codex app-server --listen \(codexServerListenURL)`."
        }
    }

    private var codexServerStartDisabled: Bool {
        if codexServerListenURLValidationError != nil { return true }
        switch codexServerController.status {
        case .starting, .running, .stopping:
            return true
        case .stopped, .failed:
            return false
        }
    }

    private var codexServerStopDisabled: Bool {
        switch codexServerController.status {
        case .running, .starting:
            return false
        case .stopped, .stopping, .failed:
            return true
        }
    }

    private var codexServerForceStopDisabled: Bool {
        switch codexServerController.status {
        case .stopping, .failed:
            return false
        default:
            return !codexServerController.hasManagedProcesses
        }
    }

    private var codexServerListenURL: String {
        let fallback = ProviderType.codexAppServer.defaultBaseURL ?? "ws://127.0.0.1:4500"
        let trimmed = (provider.baseURL ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private var codexServerListenURLValidationError: String? {
        let listen = codexServerListenURL
        guard let parsed = URL(string: listen),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            return "Base URL must be a valid ws:// or wss:// listen address to launch app-server."
        }

        guard let host = parsed.host?.lowercased(),
              host == "127.0.0.1" || host == "localhost" || host == "::1" else {
            return "In-app app-server launch only supports localhost listen addresses."
        }
        return nil
    }

    private func startCodexServer() {
        codexServerLaunchError = nil

        if let validation = codexServerListenURLValidationError {
            codexServerLaunchError = validation
            return
        }

        do {
            try codexServerController.start(listenURL: codexServerListenURL)
        } catch {
            codexServerLaunchError = error.localizedDescription
        }
    }

    private func stopCodexServer() {
        codexServerLaunchError = nil
        codexServerController.stop()
    }

    private func forceStopCodexServer() {
        codexServerLaunchError = nil
        codexServerController.forceStopManagedServers()
    }

    private var codexAuthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Authentication", selection: $codexAuthMode) {
                Text("ChatGPT").tag(CodexAuthMode.chatGPT)
                Text("API Key").tag(CodexAuthMode.apiKey)
                Text("Use Codex Login").tag(CodexAuthMode.localCodex)
            }
            .pickerStyle(.segmented)

            switch codexAuthMode {
            case .apiKey:
                apiKeyField
            case .chatGPT:
                codexChatGPTAccountSection
            case .localCodex:
                codexLocalAuthSection
            }
        }
    }

    private var codexWorkingDirectoryPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: JinSpacing.small) {
                Label("Working Directory Presets", systemImage: "folder.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Manage…") {
                    codexWorkingDirectoryPresetsDraft = codexWorkingDirectoryPresets
                    showingCodexWorkingDirectoryPresetsSheet = true
                }
                .buttonStyle(.borderless)
            }

            if codexWorkingDirectoryPresets.isEmpty {
                Text("No presets configured.")
                    .jinInfoCallout()
            } else {
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("\(codexWorkingDirectoryPresets.count) preset(s) available in chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: JinSpacing.xSmall) {
                            ForEach(codexWorkingDirectoryPresets.prefix(4)) { preset in
                                Text(preset.name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, JinSpacing.small)
                                    .padding(.vertical, 4)
                                    .jinSurface(.outlined, cornerRadius: JinRadius.small)
                            }
                            if codexWorkingDirectoryPresets.count > 4 {
                                Text("+\(codexWorkingDirectoryPresets.count - 4) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var codexLocalAuthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let hasLocalKey = CodexLocalAuthStore.loadAPIKey() != nil
            let authPath = CodexLocalAuthStore.authFileURL().path

            HStack(spacing: 6) {
                Circle()
                    .fill(hasLocalKey ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(hasLocalKey ? "Local key available" : "No local key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Reusing the API key stored by your local Codex CLI in `\(authPath)`.")
                .foregroundStyle(.secondary)

            if !hasLocalKey {
                Text("No `OPENAI_API_KEY` found yet. Run `codex login` or update your local auth file first.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var codexChatGPTAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(codexAuthStatusColor)
                    .frame(width: 8, height: 8)
                Text(codexAuthStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(codexAuthStatusMessage)
                .foregroundStyle(.secondary)

            if let codexRateLimit {
                Text(formatCodexRateLimit(codexRateLimit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    connectCodexChatGPTAccount()
                } label: {
                    Label("Connect ChatGPT", systemImage: "person.badge.key")
                }
                .buttonStyle(.borderless)
                .disabled(codexAuthStatus == .working)

                Button {
                    Task { await refreshCodexAccountStatus(forceRefreshToken: true) }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(codexAuthStatus == .working)

                Button(role: .destructive) {
                    disconnectCodexChatGPTAccount()
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .disabled(codexAuthStatus == .working || codexAccount?.isAuthenticated != true)

                if codexAuthStatus == .working {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var codexAuthStatusLabel: String {
        switch codexAuthStatus {
        case .idle:
            return "Not checked"
        case .working:
            return "Working"
        case .connected:
            return "Connected"
        case .failure:
            return "Failed"
        }
    }

    private var codexAuthStatusColor: Color {
        switch codexAuthStatus {
        case .connected:
            return .green
        case .working:
            return .orange
        case .idle, .failure:
            return .secondary
        }
    }

    private var codexAuthStatusMessage: String {
        switch codexAuthStatus {
        case .idle:
            return "Use Connect ChatGPT to open browser login."
        case .working:
            return "Waiting for ChatGPT account authorization..."
        case .connected:
            let name = codexAccount?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = codexAccount?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty, let email, !email.isEmpty {
                return "Logged in as \(name) (\(email))."
            }
            if let email, !email.isEmpty {
                return "Logged in as \(email)."
            }
            if let mode = codexAccount?.authMode, !mode.isEmpty {
                return "Account is authenticated via \(mode)."
            }
            return "Account is authenticated."
        case .failure(let message):
            return message
        }
    }

    private func formatCodexRateLimit(_ rateLimit: CodexAppServerAdapter.RateLimitStatus) -> String {
        var parts: [String] = []
        parts.append("Rate limit: \(rateLimit.name)")

        if let usedPercentage = rateLimit.usedPercentage {
            parts.append("\(usedPercentage.formatted(.number.precision(.fractionLength(0...2))))% used")
        }
        if let windowMinutes = rateLimit.windowMinutes {
            parts.append("window \(windowMinutes)m")
        }
        if let resetsAt = rateLimit.resetsAt {
            parts.append("resets \(resetsAt.formatted(date: .omitted, time: .shortened))")
        }

        return parts.joined(separator: " · ")
    }

    private var codexCanUseCurrentAuthenticationMode: Bool {
        switch codexAuthMode {
        case .apiKey:
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .chatGPT:
            return codexAccount?.isAuthenticated == true && codexAuthStatus == .connected
        case .localCodex:
            return CodexLocalAuthStore.loadAPIKey() != nil
        }
    }

    // MARK: - OpenRouter Usage

    private var openRouterUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(openRouterUsageStatusColor)
                        .frame(width: 8, height: 8)
                    Text(openRouterUsageStatusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let usage = openRouterUsage {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)

                    Text("Current key used \(formatUSD(usage.used)) (Remaining: \(usage.remainingText(formatter: formatUSD)))")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(openRouterUsageStatusColor)
                        .frame(width: 8, height: 8)

                    Text(openRouterUsageHintText)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    Task { await refreshOpenRouterUsage(force: true) }
                } label: {
                    Label("Refresh Usage", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isOpenRouterUsageRefreshDisabled)

                if openRouterUsageStatus == .loading {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                Spacer()
            }

            if case .failure(let message) = openRouterUsageStatus {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Vertex AI Section

    private var vertexAISection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Service Account JSON")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $serviceAccountJSON)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .jinTextEditorField(cornerRadius: JinRadius.small)
                .overlay(alignment: .topLeading) {
                    if serviceAccountJSON.isEmpty {
                        Text("Paste JSON content here…")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Test Connection Button

    private var testConnectionButton: some View {
        HStack {
            Button("Test Connection") {
                testConnection()
            }
            .disabled(isTestDisabled)

            if testStatus == .testing {
                ProgressView().scaleEffect(0.5)
            }

            Spacer()

            switch testStatus {
            case .idle, .testing:
                EmptyView()
            case .success:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }

    private var decodedModels: [ModelInfo] {
        provider.allModels
    }

    private var filteredModels: [ModelInfo] {
        let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return decodedModels }

        return decodedModels.filter { model in
            model.name.lowercased().contains(query) || model.id.lowercased().contains(query)
        }
    }

    private var enabledModelCount: Int {
        decodedModels.filter(\.isEnabled).count
    }

    private var fullySupportedModelsCount: Int {
        decodedModels.filter { isFullySupportedModel($0.id) }.count
    }

    private var nonFullySupportedModelsCount: Int {
        decodedModels.count - fullySupportedModelsCount
    }

    private var disabledModelCount: Int {
        decodedModels.count - enabledModelCount
    }

    private var canKeepFullySupportedModels: Bool {
        guard providerType != nil else { return false }
        return fullySupportedModelsCount > 0 && nonFullySupportedModelsCount > 0
    }

    private var canKeepEnabledModels: Bool {
        enabledModelCount > 0 && disabledModelCount > 0
    }

    private func setModels(_ models: [ModelInfo]) {
        do {
            provider.modelsData = try JSONEncoder().encode(models)
            try? modelContext.save()
        } catch {
            modelsError = error.localizedDescription
        }
    }

    private func updateModel(_ updated: ModelInfo) {
        var models = decodedModels
        guard let index = models.firstIndex(where: { $0.id == updated.id }) else { return }
        models[index] = updated
        setModels(models)
    }

    private func modelEnabledBinding(modelID: String) -> Binding<Bool> {
        Binding(
            get: {
                decodedModels.first(where: { $0.id == modelID })?.isEnabled ?? true
            },
            set: { isEnabled in
                var models = decodedModels
                guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
                models[index].isEnabled = isEnabled
                setModels(models)
            }
        )
    }

    private func setAllModelsEnabled(_ enabled: Bool) {
        guard !decodedModels.isEmpty else { return }
        let models = decodedModels.map { model in
            ModelInfo(
                id: model.id,
                name: model.name,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                maxOutputTokens: model.maxOutputTokens,
                reasoningConfig: model.reasoningConfig,
                overrides: model.overrides,
                catalogMetadata: model.catalogMetadata,
                isEnabled: enabled
            )
        }
        setModels(models)
    }

    private func keepOnlyFullySupportedModels() {
        guard providerType != nil else { return }
        let filteredModels = decodedModels.filter { isFullySupportedModel($0.id) }
        guard !filteredModels.isEmpty else { return }
        setModels(filteredModels)
    }

    private func keepOnlyEnabledModels() {
        let filteredModels = decodedModels.filter(\.isEnabled)
        guard !filteredModels.isEmpty, filteredModels.count < decodedModels.count else { return }
        setModels(filteredModels)
    }

    private func requestDeleteModel(_ model: ModelInfo) {
        modelPendingDeletion = model
        showingDeleteModelConfirmation = true
    }

    private func deleteModel(_ model: ModelInfo) {
        var updatedModels = decodedModels
        guard let index = updatedModels.firstIndex(where: { $0.id == model.id }) else {
            modelPendingDeletion = nil
            return
        }
        updatedModels.remove(at: index)
        setModels(updatedModels)
        modelPendingDeletion = nil
    }

    private func loadCodexWorkingDirectoryPresets() {
        codexWorkingDirectoryPresets = CodexWorkingDirectoryPresetsStore.load()
    }

    private func persistCodexWorkingDirectoryPresets() {
        CodexWorkingDirectoryPresetsStore.save(codexWorkingDirectoryPresets)
        codexWorkingDirectoryPresets = CodexWorkingDirectoryPresetsStore.load()
    }

    // MARK: - Actions

    private func loadCredentials() async {
        await MainActor.run {
            switch ProviderType(rawValue: provider.typeRaw) {
            case .codexAppServer:
                let storedKey = provider.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                apiKey = storedKey
                if provider.apiKeyKeychainID == CodexLocalAuthStore.authModeHint {
                    codexAuthMode = .localCodex
                } else {
                    codexAuthMode = storedKey.isEmpty ? .chatGPT : .apiKey
                }
                codexAuthStatus = .idle
                codexAccount = nil
                codexRateLimit = nil
                codexPendingLoginID = nil
            case .githubCopilot:
                apiKey = provider.apiKey ?? ""
            case .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
                 .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai,
                 .deepseek, .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini:
                apiKey = provider.apiKey ?? ""
            case .vertexai:
                serviceAccountJSON = provider.serviceAccountJSON ?? ""
            case .none:
                break
            }
        }
    }

    private func testConnection() {
        testStatus = .testing

        Task {
            do {
                try await saveCredentials()

                guard let config = try? provider.toDomain() else {
                    testStatus = .failure("Invalid configuration")
                    return
                }

                let isValid = try await providerManager.validateConfiguration(for: config)
                testStatus = isValid ? .success : .failure("Connection failed")
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func saveCredentials() async throws {
        credentialSaveTask?.cancel()
        credentialSaveTask = nil
        try await persistCredentials(validate: true)
    }

    private func scheduleCredentialSave() {
        credentialSaveTask?.cancel()
        credentialSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)

            do {
                try await persistCredentials(validate: false)
                await MainActor.run { credentialSaveError = nil }
            } catch {
                await MainActor.run { credentialSaveError = error.localizedDescription }
            }
        }
    }

    private func scheduleOpenRouterUsageRefresh() {
        openRouterUsageTask?.cancel()
        openRouterUsageTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshOpenRouterUsage(force: true)
        }
    }

    private func refreshOpenRouterUsage(force: Bool) async {
        guard providerType == .openrouter else { return }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            await MainActor.run {
                openRouterUsage = nil
                openRouterUsageStatus = .idle
            }
            return
        }

        if !force, openRouterUsageStatus == .loading {
            return
        }

        await MainActor.run {
            openRouterUsageStatus = .loading
        }

        do {
            let usage = try await fetchOpenRouterKeyUsage(apiKey: key)
            await MainActor.run {
                openRouterUsage = usage
                openRouterUsageStatus = .observed
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                openRouterUsage = nil
                openRouterUsageStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func fetchOpenRouterKeyUsage(apiKey: String) async throws -> OpenRouterKeyUsage {
        let defaultBaseURL = ProviderType.openrouter.defaultBaseURL ?? "https://openrouter.ai/api/v1"
        let raw = (provider.baseURL ?? defaultBaseURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw

        let lower = trimmed.lowercased()
        let normalizedBaseURL: String
        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            normalizedBaseURL = trimmed
        } else if lower.hasSuffix("/api") {
            normalizedBaseURL = "\(trimmed)/v1"
        } else if let url = URL(string: trimmed), url.host?.lowercased().contains("openrouter.ai") == true {
            let path = url.path.lowercased()
            if path.isEmpty || path == "/" {
                normalizedBaseURL = "\(trimmed)/api/v1"
            } else {
                normalizedBaseURL = trimmed
            }
        } else {
            normalizedBaseURL = trimmed
        }

        guard let url = URL(string: "\(normalizedBaseURL)/key") else {
            throw LLMError.invalidRequest(message: "Invalid OpenRouter base URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

        let (data, _) = try await networkManager.sendRequest(request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterKeyResponse.self, from: data)

        let used = response.data.usage ?? 0
        var remaining: Double?
        if let limitRemaining = response.data.limitRemaining {
            remaining = max(limitRemaining, 0)
        } else if let limit = response.data.limit {
            remaining = max(limit - used, 0)
        } else {
            remaining = try await fetchOpenRouterRemainingCredits(apiKey: apiKey, baseURL: normalizedBaseURL)
        }

        return OpenRouterKeyUsage(used: used, remaining: remaining)
    }

    private func fetchOpenRouterRemainingCredits(apiKey: String, baseURL: String) async throws -> Double? {
        guard let url = URL(string: "\(baseURL)/credits") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

        let (data, _) = try await networkManager.sendRequest(request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterCreditsResponse.self, from: data)

        guard let totalCredits = response.data.totalCredits,
              let totalUsage = response.data.totalUsage else {
            return nil
        }

        return max(totalCredits - totalUsage, 0)
    }

    private func connectCodexChatGPTAccount() {
        codexAuthTask?.cancel()
        codexAuthTask = Task {
            await MainActor.run {
                codexAuthStatus = .working
                codexPendingLoginID = nil
            }

            do {
                try await saveCredentials()
                let adapter = try codexAdapterForCurrentState()
                let challenge = try await adapter.startChatGPTLogin()
                await MainActor.run {
                    codexPendingLoginID = challenge.loginID
                    openURL(challenge.authURL)
                }

                try await waitForCodexChatGPTAuthentication(
                    adapter: adapter,
                    loginID: challenge.loginID,
                    timeoutSeconds: 180
                )
                await refreshCodexAccountStatus(forceRefreshToken: true)
            } catch is CancellationError {
                if let loginID = await MainActor.run(body: { codexPendingLoginID }) {
                    try? await codexAdapterForCurrentState().cancelChatGPTLogin(loginID: loginID)
                }
            } catch {
                await MainActor.run {
                    codexAuthStatus = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func disconnectCodexChatGPTAccount() {
        codexAuthTask?.cancel()
        codexAuthTask = Task {
            await MainActor.run { codexAuthStatus = .working }
            do {
                try await saveCredentials()
                try await codexAdapterForCurrentState().logoutAccount()
                await MainActor.run {
                    codexAccount = nil
                    codexRateLimit = nil
                    codexPendingLoginID = nil
                    codexAuthStatus = .idle
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    codexAuthStatus = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func refreshCodexAccountStatus(forceRefreshToken: Bool) async {
        guard providerType == .codexAppServer, codexAuthMode == .chatGPT else { return }
        await MainActor.run { codexAuthStatus = .working }

        do {
            try await saveCredentials()
            let adapter = try codexAdapterForCurrentState()
            let status = try await adapter.readAccountStatus(refreshToken: forceRefreshToken)
            let rateLimit = try? await adapter.readPrimaryRateLimit()
            await MainActor.run {
                codexAccount = status
                codexRateLimit = rateLimit
                codexPendingLoginID = nil
                codexAuthStatus = status.isAuthenticated ? .connected : .idle
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                codexAccount = nil
                codexRateLimit = nil
                codexAuthStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func waitForCodexChatGPTAuthentication(
        adapter: CodexAppServerAdapter,
        loginID: String,
        timeoutSeconds: Int
    ) async throws {
        _ = try await adapter.waitForChatGPTLoginCompletion(
            loginID: loginID,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func codexAdapterForCurrentState() throws -> CodexAppServerAdapter {
        guard providerType == .codexAppServer else {
            throw LLMError.invalidRequest(message: "Current provider is not Codex App Server.")
        }

        let key: String
        switch codexAuthMode {
        case .apiKey:
            key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .chatGPT:
            key = ""
        case .localCodex:
            guard let localKey = CodexLocalAuthStore.loadAPIKey() else {
                throw LLMError.invalidRequest(
                    message: "No OPENAI_API_KEY found in \(CodexLocalAuthStore.authFileURL().path)."
                )
            }
            key = localKey
        }

        let config = ProviderConfig(
            id: provider.id,
            name: provider.name,
            type: .codexAppServer,
            iconID: provider.iconID,
            authModeHint: codexAuthMode == .localCodex ? CodexLocalAuthStore.authModeHint : nil,
            apiKey: key.isEmpty ? nil : key,
            serviceAccountJSON: nil,
            baseURL: provider.baseURL,
            models: decodedModels
        )

        return CodexAppServerAdapter(providerConfig: config, apiKey: key, networkManager: networkManager)
    }

    private func persistCredentials(validate: Bool) async throws {
        switch ProviderType(rawValue: provider.typeRaw) {
        case .codexAppServer:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                provider.apiKeyKeychainID = codexAuthMode == .localCodex ? CodexLocalAuthStore.authModeHint : nil
                provider.apiKey = (codexAuthMode == .apiKey && !key.isEmpty) ? key : nil
                provider.serviceAccountJSON = nil
                try? modelContext.save()
            }

        case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                provider.apiKeyKeychainID = nil
                provider.apiKey = key.isEmpty ? nil : key
                provider.serviceAccountJSON = nil
                try? modelContext.save()
            }

        case .vertexai:
            let json = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)

            if validate {
                _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(json.utf8))
            }

            await MainActor.run {
                provider.apiKeyKeychainID = nil
                provider.serviceAccountJSON = json.isEmpty ? nil : json
                provider.apiKey = nil
                try? modelContext.save()
            }

        case .none:
            break
        }
    }

    private func fetchModels() async {
        guard !isFetchingModels else { return }

        await MainActor.run {
            isFetchingModels = true
            modelsError = nil
        }

        defer {
            Task { @MainActor in isFetchingModels = false }
        }

        do {
            try await saveCredentials()
            guard let config = try? provider.toDomain() else {
                throw PersistenceError.invalidProviderType(provider.typeRaw)
            }
            let adapter = try await providerManager.createAdapter(for: config)
            let fetched = try await adapter.fetchAvailableModels()
            var seenIDs = Set<String>()
            let deduplicated = fetched.filter { seenIDs.insert($0.id).inserted }
            let sorted = deduplicated.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await MainActor.run {
                if sorted.isEmpty {
                    fetchedModelsForSelection = nil
                    modelsError = "No models were returned by this provider."
                } else {
                    fetchedModelsForSelection = FetchedModelsSelectionState(models: sorted)
                }
            }
        } catch {
            await MainActor.run { modelsError = error.localizedDescription }
        }
    }

    /// Adds user-selected new models AND silently refreshes metadata for all
    /// existing models that appeared in the fetch, regardless of selection.
    /// User overrides and enabled state are always preserved.
    private func addSelectedAndRefreshExisting(selected: [ModelInfo], allFetched: [ModelInfo]) -> [ModelInfo] {
        let existingByID = decodedModels.reduce(into: [String: ModelInfo]()) { $0[$1.id] = $1 }
        let fetchedByID = allFetched.reduce(into: [String: ModelInfo]()) { $0[$1.id] = $1 }
        var resultByID = existingByID

        func mergedModel(from fetched: ModelInfo, preserving existing: ModelInfo) -> ModelInfo {
            ModelInfo(
                id: fetched.id,
                name: fetched.name,
                capabilities: fetched.capabilities,
                contextWindow: fetched.contextWindow,
                maxOutputTokens: fetched.maxOutputTokens,
                reasoningConfig: fetched.reasoningConfig,
                overrides: existing.overrides,
                catalogMetadata: fetched.catalogMetadata,
                isEnabled: existing.isEnabled
            )
        }

        // Refresh metadata for existing models that appeared in the fetch
        for (id, fetched) in fetchedByID where existingByID[id] != nil {
            let existing = existingByID[id]!
            resultByID[id] = mergedModel(from: fetched, preserving: existing)
        }

        if providerType == .githubCopilot {
            for (legacyID, existing) in existingByID where fetchedByID[legacyID] == nil {
                guard let migrated = ProviderModelAliasResolver.resolvedModel(
                    for: legacyID,
                    providerType: .githubCopilot,
                    availableModels: allFetched
                ), migrated.id != legacyID else {
                    continue
                }
                resultByID.removeValue(forKey: legacyID)
                resultByID[migrated.id] = mergedModel(from: migrated, preserving: existing)
            }
        }

        // Add newly selected models that don't already exist
        for model in selected where existingByID[model.id] == nil {
            resultByID[model.id] = ModelInfo(
                id: model.id,
                name: model.name,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                maxOutputTokens: model.maxOutputTokens,
                reasoningConfig: model.reasoningConfig,
                overrides: nil,
                catalogMetadata: model.catalogMetadata,
                isEnabled: true
            )
        }

        return resultByID.values.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Helpers

    private var isTestDisabled: Bool {
        switch ProviderType(rawValue: provider.typeRaw) {
        case .codexAppServer:
            return !codexCanUseCurrentAuthenticationMode || testStatus == .testing || codexAuthStatus == .working
        case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testStatus == .testing
        case .vertexai:
            return serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testStatus == .testing
        case .none:
            return true
        }
    }

    private var isFetchModelsDisabled: Bool {
        guard !isFetchingModels else { return true }
        switch providerType {
        case .codexAppServer:
            return !codexCanUseCurrentAuthenticationMode || codexAuthStatus == .working
        case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .gemini:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vertexai:
            return serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .none:
            return true
        }
    }

    private var isOpenRouterUsageRefreshDisabled: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || openRouterUsageStatus == .loading
    }

    private var openRouterUsageStatusLabel: String {
        switch openRouterUsageStatus {
        case .idle, .failure:
            return "Not observed"
        case .loading:
            return "Checking"
        case .observed:
            return "Observed"
        }
    }

    private var openRouterUsageStatusColor: Color {
        switch openRouterUsageStatus {
        case .observed:
            return .green
        case .loading:
            return .orange
        case .idle, .failure:
            return .secondary
        }
    }

    private var openRouterUsageHintText: String {
        switch openRouterUsageStatus {
        case .idle:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Enter an API key to check usage."
                : "Usage not fetched yet."
        case .loading:
            return "Fetching current key usage..."
        case .observed:
            return "No usage data returned for this key."
        case .failure:
            return "Failed to fetch usage for this key."
        }
    }

    private func formatUSD(_ value: Double) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(0...8)))
    }

    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    enum CodexAuthMode: String, CaseIterable {
        case apiKey
        case chatGPT
        case localCodex
    }

    enum CodexAuthStatus: Equatable {
        case idle
        case working
        case connected
        case failure(String)
    }
}
