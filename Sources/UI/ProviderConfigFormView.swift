import SwiftUI
import SwiftData

struct ProviderConfigFormView: View {
    @Bindable var provider: ProviderConfigEntity
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""
    @State private var showingAPIKey = false
    @State private var storeCredentialsInKeychain = true
    @State private var hasInitializedCredentialStorage = false
    @State private var credentialSaveError: String?
    @State private var credentialSaveTask: Task<Void, Never>?
    @State private var testStatus: TestStatus = .idle
    @State private var isFetchingModels = false
    @State private var modelsError: String?
    @State private var showingAddModel = false
    @State private var showingDeleteAllModelsConfirmation = false
    @State private var selectedModelIDs: Set<ModelInfo.ID> = []

    private let providerManager = ProviderManager()
    private let keychainManager = KeychainManager()

    var body: some View {
        Form {
            Section("Configuration") {
                TextField("Name", text: $provider.name)

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

                Toggle("Store credentials in Keychain", isOn: $storeCredentialsInKeychain)
                    .help("Keychain is more secure, but unsigned builds may prompt for your Mac password.")

                if storeCredentialsInKeychain {
                    Text("Keychain mode can prompt repeatedly when running unsigned builds (e.g. `swift run`). Run via Xcode (signed) or turn this off to store locally.")
                        .jinInfoCallout()
                } else {
                    Text("Credentials are stored locally in your app database (less secure, but no Keychain prompts).")
                        .jinInfoCallout()
                }

                switch providerType {
                case .openai, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini:
                    apiKeyField
                case .vertexai:
                    vertexAISection
                case .none:
                    Text("Unknown provider type")
                        .foregroundColor(.secondary)
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
                
                if decodedModels.isEmpty {
                    Text("No models found. Fetch from provider or add manually.")
                        .jinInfoCallout()
                 } else {
                     List(decodedModels, selection: $selectedModelIDs) { model in
                         HStack {
                             Text(model.name)
                             if isFullySupportedModel(model.id) {
                                 Text("Full")
                                     .jinTagStyle(foreground: .green)
                             }
                             Spacer()
                             Text(model.id)
                                 .foregroundStyle(.secondary)
                                 .font(.caption)
                         }
                     }
                     .frame(minHeight: 150)
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
                hasInitializedCredentialStorage = true
            }
        }
        .onChange(of: storeCredentialsInKeychain) { _, newValue in
            guard hasInitializedCredentialStorage else { return }
            handleCredentialStorageModeChanged(storeInKeychain: newValue)
        }
        .onChange(of: apiKey) { _, _ in
            guard hasInitializedCredentialStorage else { return }
            scheduleCredentialSave()
        }
        .onChange(of: serviceAccountJSON) { _, _ in
            guard hasInitializedCredentialStorage else { return }
            scheduleCredentialSave()
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
        let lower = modelID.lowercased()

        switch providerType {
        case .fireworks:
            return lower == "fireworks/kimi-k2p5"
                || lower == "accounts/fireworks/models/kimi-k2p5"
                || lower == "fireworks/glm-4p7"
                || lower == "accounts/fireworks/models/glm-4p7"
        case .cerebras:
            return lower == "zai-glm-4.7"
        case .gemini:
            return lower.contains("gemini-3") || lower.contains("gemini-2.5-flash-image")
        case .vertexai:
            return lower.contains("gemini-3") || lower.contains("gemini-2.5")
        case .openai, .anthropic, .xai, .deepseek:
            return false
        }
    }

    private func baseURLBinding(defaultBaseURL: String) -> Binding<String> {
        Binding(
            get: { provider.baseURL ?? defaultBaseURL },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    provider.baseURL = defaultBaseURL
                    return
                }
                provider.baseURL = trimmed
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
        (try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData)) ?? []
    }

    private func setModels(_ models: [ModelInfo]) {
        do {
            provider.modelsData = try JSONEncoder().encode(models)
            selectedModelIDs = []
        } catch {
            modelsError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func loadCredentials() async {
        let usesKeychain = provider.apiKeyKeychainID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        await MainActor.run {
            storeCredentialsInKeychain = usesKeychain
        }

        switch ProviderType(rawValue: provider.typeRaw) {
        case .openai, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini:
            if usesKeychain {
                await MainActor.run { apiKey = "" }
            } else {
                apiKey = provider.apiKey ?? ""
            }
        case .vertexai:
            if usesKeychain {
                await MainActor.run { serviceAccountJSON = "" }
            } else {
                serviceAccountJSON = provider.serviceAccountJSON ?? ""
            }
        case .none:
            break
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

    private func handleCredentialStorageModeChanged(storeInKeychain: Bool) {
        credentialSaveTask?.cancel()
        credentialSaveTask = nil
        credentialSaveError = nil

        Task {
            do {
                if storeInKeychain {
                    await MainActor.run {
                        provider.apiKeyKeychainID = provider.id
                        provider.apiKey = nil
                        provider.serviceAccountJSON = nil
                    }
                    try await persistCredentialsToKeychain(validate: false)
                } else {
                    try await persistCredentialsLocally(validate: false)
                    await MainActor.run {
                        provider.apiKeyKeychainID = nil
                    }

                    let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedJSON = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                    switch ProviderType(rawValue: provider.typeRaw) {
                    case .openai, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini:
                        if trimmedAPIKey.isEmpty {
                            await MainActor.run {
                                credentialSaveError = "Keychain disabled. Paste your API key again to use this provider."
                            }
                        }
                    case .vertexai:
                        if trimmedJSON.isEmpty {
                            await MainActor.run {
                                credentialSaveError = "Keychain disabled. Paste your service account JSON again to use this provider."
                            }
                        }
                    case .none:
                        break
                    }
                }
            } catch {
                await MainActor.run {
                    credentialSaveError = error.localizedDescription
                }
            }
        }
    }

    private func persistCredentials(validate: Bool) async throws {
        if storeCredentialsInKeychain {
            try await persistCredentialsToKeychain(validate: validate)
        } else {
            try await persistCredentialsLocally(validate: validate)
        }
    }

    private func persistCredentialsToKeychain(validate: Bool) async throws {
        let keychainID = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keychainID.isEmpty else { return }

        switch ProviderType(rawValue: provider.typeRaw) {
        case .openai, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                provider.apiKeyKeychainID = keychainID
                provider.apiKey = nil
                provider.serviceAccountJSON = nil
            }

            if key.isEmpty {
                return
            }

            try await keychainManager.saveAPIKey(key, for: keychainID)

        case .vertexai:
            let json = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                provider.apiKeyKeychainID = keychainID
                provider.apiKey = nil
                provider.serviceAccountJSON = nil
            }

            if json.isEmpty {
                return
            }

            if validate {
                _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(json.utf8))
            }

            try await keychainManager.saveServiceAccountJSON(json, for: keychainID)

        case .none:
            break
        }
    }

    private func persistCredentialsLocally(validate: Bool) async throws {
        switch ProviderType(rawValue: provider.typeRaw) {
        case .openai, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                provider.apiKeyKeychainID = nil
                provider.apiKey = key.isEmpty ? nil : key
                provider.serviceAccountJSON = nil
            }

        case .vertexai:
            let json = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if validate, !json.isEmpty {
                _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(json.utf8))
            }
            await MainActor.run {
                provider.apiKeyKeychainID = nil
                provider.serviceAccountJSON = json.isEmpty ? nil : json
                provider.apiKey = nil
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
            let models = try await adapter.fetchAvailableModels()
            await MainActor.run { setModels(models) }
        } catch {
            await MainActor.run { modelsError = error.localizedDescription }
        }
    }

    // MARK: - Helpers

    private var isTestDisabled: Bool {
        switch ProviderType(rawValue: provider.typeRaw) {
        case .openai, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini:
            return (!storeCredentialsInKeychain && apiKey.isEmpty) || testStatus == .testing
        case .vertexai:
            return (!storeCredentialsInKeychain && serviceAccountJSON.isEmpty) || testStatus == .testing
        case .none:
            return true
        }
    }

    private var isFetchModelsDisabled: Bool {
        guard !isFetchingModels else { return true }
        switch providerType {
        case .openai, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini:
            return !storeCredentialsInKeychain && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vertexai:
            return !storeCredentialsInKeychain && serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .none:
            return true
        }
    }

    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }
}

private struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss

    let providerType: ProviderType?
    let onAdd: (ModelInfo) -> Void

    @State private var nickname = ""
    @State private var modelID = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nickname", text: $nickname)
                TextField("Model ID", text: $modelID)
                    .font(.system(.body, design: .monospaced))
            }
            .navigationTitle("Add Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                        let nameToUse = trimmedName.isEmpty ? trimmedID : trimmedName

                        onAdd(makeModelInfo(id: trimmedID, name: nameToUse))
                        dismiss()
                    }
                    .disabled(modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }

    private func makeModelInfo(id: String, name: String) -> ModelInfo {
        let lower = id.lowercased()

        var caps: ModelCapability = [.streaming, .toolCalling]
        let contextWindow = 128000
        var reasoningConfig: ModelReasoningConfig?

        switch providerType {
        case .fireworks?:
            if lower == "fireworks/kimi-k2p5" || lower == "accounts/fireworks/models/kimi-k2p5" {
                caps.insert(.vision)
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            } else if lower == "fireworks/glm-4p7" || lower == "accounts/fireworks/models/glm-4p7" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }

        case .cerebras?:
            if lower == "zai-glm-4.7" {
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .toggle)
            }

        case .gemini?:
            if lower.contains("gemini-3-pro-image") {
                caps = [.streaming, .vision, .reasoning, .imageGeneration]
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            } else if lower.contains("-image") {
                caps = [.streaming, .vision, .imageGeneration]
                reasoningConfig = nil
            } else if lower.contains("gemini-3") {
                caps.insert(.vision)
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }

        case .vertexai?:
            if lower.contains("gemini-3-pro-image") {
                caps = [.streaming, .vision, .reasoning, .imageGeneration]
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            } else if lower.contains("-image") {
                caps = [.streaming, .vision, .imageGeneration]
                reasoningConfig = nil
            } else if lower.contains("gemini-2.5") {
                caps.insert(.vision)
                caps.insert(.reasoning)
                reasoningConfig = ModelReasoningConfig(type: .budget, defaultBudget: 2048)
            } else if lower.contains("gemini-3") {
                caps.insert(.vision)
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)
            }

        case .openai?, .anthropic?, .xai?, .deepseek?, .none:
            break
        }

        return ModelInfo(
            id: id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }
}
