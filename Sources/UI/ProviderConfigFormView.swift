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
    @State private var showingAPIKey = false
    @State private var hasLoadedCredentials = false
    @State private var credentialSaveError: String?
    @State private var credentialSaveTask: Task<Void, Never>?
    @State private var testStatus: TestStatus = .idle
    @State private var isFetchingModels = false
    @State private var modelsError: String?
    @State private var showingAddModel = false
    @State private var showingDeleteAllModelsConfirmation = false
    @State private var modelSearchText = ""
    @State private var editingModel: ModelInfo?
    @State private var openRouterUsageStatus: OpenRouterUsageStatus = .idle
    @State private var openRouterUsage: OpenRouterKeyUsage?
    @State private var openRouterUsageTask: Task<Void, Never>?

    @AppStorage(AppPreferenceKeys.allowAutomaticNetworkRequests) private var allowAutomaticNetworkRequests = false

    private let providerManager = ProviderManager()
    private let networkManager = NetworkManager()

    var body: some View {
        Form {
            Section("Configuration") {
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
                    .help("Default endpoint is pre-filled. Change only if you know what you’re doing.")

                    if providerType == .cerebras {
                        let base = (provider.baseURL ?? defaultBaseURL).lowercased()
                        if base.contains("cerebras-sandbox.net") {
                            Text("Warning: cerebras-sandbox.net is the web sandbox and is Cloudflare-protected. Use the API endpoint https://api.cerebras.ai/v1 instead.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if !base.contains("api.cerebras.ai") {
                            Text("Tip: Cerebras OpenAI-compatible base URL is https://api.cerebras.ai/v1.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Credentials are stored locally in your app database.")
                    .jinInfoCallout()

                switch providerType {
                case .codexAppServer:
                    codexServerSection
                    codexAuthSection
                case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini:
                    apiKeyField
                case .vertexai:
                    vertexAISection
                case .none:
                    Text("Unknown provider type")
                        .foregroundColor(.secondary)
                }

                if providerType == .codexAppServer {
                    Text("You can start/stop `codex app-server` here. Choose one auth mode only: API Key, ChatGPT Account, or Local Codex Auth file.")
                        .jinInfoCallout()
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

                    HStack(spacing: 10) {
                        Text("Enabled \(enabledModelCount) / \(decodedModels.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Enable All") {
                            setAllModelsEnabled(true)
                        }
                        .buttonStyle(.borderless)

                        Button("Disable All") {
                            setAllModelsEnabled(false)
                        }
                        .buttonStyle(.borderless)
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
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Model Settings")

                            Toggle("", isOn: modelEnabledBinding(modelID: model.id))
                                .labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingModel = model
                        }
                    }
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .background(JinSemanticColor.detailSurface)
                    .jinSurface(.raised, cornerRadius: JinRadius.medium)
                }

                HStack {
                    Button("Fetch Models") {
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .task {
            await loadCredentials()
            await MainActor.run {
                hasLoadedCredentials = true
            }
            if providerType == .openrouter, allowAutomaticNetworkRequests {
                await refreshOpenRouterUsage(force: true)
            }
            if providerType == .codexAppServer, codexAuthMode == .chatGPT, allowAutomaticNetworkRequests {
                await refreshCodexAccountStatus(forceRefreshToken: false)
            }
        }
        .onChange(of: apiKey) { _, _ in
            guard hasLoadedCredentials else { return }
            scheduleCredentialSave()
            if providerType == .openrouter, allowAutomaticNetworkRequests {
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
        .sheet(isPresented: $showingAddModel) {
            AddModelSheet(
                providerType: providerType,
                onAdd: { model in
                    var models = decodedModels
                    models.append(model)
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
        HStack {
            if showingAPIKey {
                TextField("API Key", text: $apiKey)
            } else {
                SecureField("API Key", text: $apiKey)
            }

            Button(action: { showingAPIKey.toggle() }) {
                Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(JinIconButtonStyle())
        }
    }

    // MARK: - Codex Auth

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

    private var codexAuthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Authentication", selection: $codexAuthMode) {
                Text("API Key").tag(CodexAuthMode.apiKey)
                Text("ChatGPT Account").tag(CodexAuthMode.chatGPT)
                Text("Local Codex").tag(CodexAuthMode.localCodex)
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

            Text("Reading API key from `\(authPath)`.")
                .foregroundStyle(.secondary)

            if !hasLocalKey {
                Text("No OPENAI_API_KEY found. Update your Codex login/auth first.")
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
                .padding(JinSpacing.small)
                .jinSurface(.raised, cornerRadius: JinRadius.small)
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
                reasoningConfig: model.reasoningConfig,
                overrides: model.overrides,
                isEnabled: enabled
            )
        }
        setModels(models)
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
            case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini:
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

        case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini:
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
            let fetchedModels = try await adapter.fetchAvailableModels()
            await MainActor.run {
                let merged = mergeFetchedModelsWithExisting(fetchedModels)
                setModels(merged)
            }
        } catch {
            await MainActor.run { modelsError = error.localizedDescription }
        }
    }

    private func mergeFetchedModelsWithExisting(_ fetchedModels: [ModelInfo]) -> [ModelInfo] {
        let previousByID = Dictionary(uniqueKeysWithValues: decodedModels.map { ($0.id, $0) })

        var merged: [ModelInfo] = []
        var seenIDs: Set<String> = []
        merged.reserveCapacity(fetchedModels.count)

        for model in fetchedModels {
            guard !seenIDs.contains(model.id) else { continue }
            seenIDs.insert(model.id)

            let isEnabled = previousByID[model.id]?.isEnabled ?? true
            let overrides = previousByID[model.id]?.overrides
            merged.append(
                ModelInfo(
                    id: model.id,
                    name: model.name,
                    capabilities: model.capabilities,
                    contextWindow: model.contextWindow,
                    reasoningConfig: model.reasoningConfig,
                    overrides: overrides,
                    isEnabled: isEnabled
                )
            )
        }

        return merged.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Helpers

    private var isTestDisabled: Bool {
        switch ProviderType(rawValue: provider.typeRaw) {
        case .codexAppServer:
            if codexAuthMode == .apiKey {
                return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testStatus == .testing
            }
            if codexAuthMode == .localCodex {
                return CodexLocalAuthStore.loadAPIKey() == nil || testStatus == .testing
            }
            return testStatus == .testing || codexAuthStatus == .working
        case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini:
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
            if codexAuthMode == .apiKey {
                return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if codexAuthMode == .localCodex {
                return CodexLocalAuthStore.loadAPIKey() == nil
            }
            return codexAuthStatus == .working
        case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini:
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
