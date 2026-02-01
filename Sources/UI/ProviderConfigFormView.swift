import SwiftUI
import SwiftData

struct ProviderConfigFormView: View {
    @Bindable var provider: ProviderConfigEntity
    @State private var apiKey = ""
    @State private var serviceAccountJSON = ""
    @State private var showingAPIKey = false
    @State private var testStatus: TestStatus = .idle
    @State private var isFetchingModels = false
    @State private var modelsError: String?
    @State private var showingAddModel = false
    @State private var showingDeleteAllModelsConfirmation = false
    @State private var selectedModelIDs: Set<ModelInfo.ID> = []

    private let providerManager = ProviderManager()

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
                }

                switch providerType {
                case .openai, .anthropic, .xai:
                    apiKeyField
                case .vertexai:
                    vertexAISection
                case .none:
                    Text("Unknown provider type")
                        .foregroundColor(.secondary)
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
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.vertical, 4)
                } else {
                     List(decodedModels, selection: $selectedModelIDs) { model in
                         HStack {
                             Text(model.name)
                             Spacer()
                             Text(model.id)
                                 .foregroundStyle(.secondary)
                                 .font(.caption)
                         }
                     }
                     .frame(minHeight: 150)
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
        .padding()
        .task {
            await loadCredentials()
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
            }
            .buttonStyle(.borderless)
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
            case .idle:
                EmptyView()
            case .testing:
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
        switch ProviderType(rawValue: provider.typeRaw) {
        case .openai, .anthropic, .xai:
            apiKey = provider.apiKey ?? ""
        case .vertexai:
            serviceAccountJSON = provider.serviceAccountJSON ?? ""
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
        switch ProviderType(rawValue: provider.typeRaw) {
        case .openai, .anthropic, .xai:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            provider.apiKey = key
            provider.serviceAccountJSON = nil

        case .vertexai:
            let json = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !json.isEmpty else { return }
            _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(json.utf8))
            provider.serviceAccountJSON = json
            provider.apiKey = nil

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
        case .openai, .anthropic, .xai:
            return apiKey.isEmpty || testStatus == .testing
        case .vertexai:
            return serviceAccountJSON.isEmpty || testStatus == .testing
        case .none:
            return true
        }
    }

    private var isFetchModelsDisabled: Bool {
        guard !isFetchingModels else { return true }
        switch providerType {
        case .openai, .anthropic, .xai:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vertexai:
            return serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

// AddModelSheet remains the same as previous read, so I don't need to rewrite it if I didn't change it.
// Wait, I am overwriting the file. I MUST include AddModelSheet.

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
        // Simple default factory
        return ModelInfo(
            id: id,
            name: name,
            capabilities: [.streaming, .toolCalling],
            contextWindow: 128000,
            reasoningConfig: nil
        )
    }
}
