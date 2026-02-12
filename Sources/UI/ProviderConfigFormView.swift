import SwiftUI
import SwiftData

struct ProviderConfigFormView: View {
    @Bindable var provider: ProviderConfigEntity
    @Environment(\.modelContext) private var modelContext
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""
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
                case .openai, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini:
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
                                }

                                Text(model.id)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }

                            Spacer(minLength: 8)

                            Toggle("", isOn: modelEnabledBinding(modelID: model.id))
                                .labelsHidden()
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
        }
        .onChange(of: apiKey) { _, _ in
            guard hasLoadedCredentials else { return }
            scheduleCredentialSave()
            if providerType == .openrouter, allowAutomaticNetworkRequests {
                scheduleOpenRouterUsageRefresh()
            }
        }
        .onChange(of: serviceAccountJSON) { _, _ in
            guard hasLoadedCredentials else { return }
            scheduleCredentialSave()
        }
        .onDisappear {
            credentialSaveTask?.cancel()
            openRouterUsageTask?.cancel()
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
                isEnabled: enabled
            )
        }
        setModels(models)
    }

    // MARK: - Actions

    private func loadCredentials() async {
        await MainActor.run {
            switch ProviderType(rawValue: provider.typeRaw) {
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

    private func persistCredentials(validate: Bool) async throws {
        switch ProviderType(rawValue: provider.typeRaw) {
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
            merged.append(
                ModelInfo(
                    id: model.id,
                    name: model.name,
                    capabilities: model.capabilities,
                    contextWindow: model.contextWindow,
                    reasoningConfig: model.reasoningConfig,
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
}

private enum OpenRouterUsageStatus: Equatable {
    case idle
    case loading
    case observed
    case failure(String)
}

private struct OpenRouterKeyUsage: Equatable {
    let used: Double
    let remaining: Double?

    func remainingText(formatter: (Double) -> String) -> String {
        guard let remaining else { return "Unavailable" }
        return formatter(remaining)
    }
}

private struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyData
}

private struct OpenRouterKeyData: Decodable {
    let usage: Double?
    let limit: Double?
    let limitRemaining: Double?
}

private struct OpenRouterCreditsResponse: Decodable {
    let data: OpenRouterCreditsData
}

private struct OpenRouterCreditsData: Decodable {
    let totalCredits: Double?
    let totalUsage: Double?
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

        case .xai?:
            if lower.contains("imagine-image")
                || lower.contains("grok-2-image")
                || lower.hasSuffix("-image") {
                caps = [.imageGeneration]
                reasoningConfig = nil
            }

        case .perplexity?:
            if lower.contains("reasoning") || lower.contains("deep-research") {
                caps.insert(.reasoning)
                caps.insert(.nativePDF)
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            }
            if lower.contains("sonar") {
                caps.insert(.vision)
                caps.insert(.nativePDF)
            }

        case .openai?, .openaiCompatible?, .openrouter?, .anthropic?, .groq?, .cohere?, .mistral?, .deepinfra?, .deepseek?, .none:
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
