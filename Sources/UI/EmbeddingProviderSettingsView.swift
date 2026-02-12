import SwiftUI
import SwiftData

struct EmbeddingProviderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var embeddingProviders: [EmbeddingProviderConfigEntity]
    @Query private var rerankProviders: [RerankProviderConfigEntity]

    @State private var selectedEmbeddingProviderID: String?
    @State private var selectedRerankProviderID: String?
    @State private var selectedTab: ProviderTab = .embedding
    @State private var isValidating = false
    @State private var validationResult: String?
    @State private var showingValidationResult = false

    private enum ProviderTab: String, CaseIterable {
        case embedding = "Embedding"
        case rerank = "Rerank"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(ProviderTab.allCases, id: \.rawValue) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            switch selectedTab {
            case .embedding:
                embeddingProvidersList
            case .rerank:
                rerankProvidersList
            }
        }
        .alert("Validation Result", isPresented: $showingValidationResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationResult ?? "")
        }
    }

    // MARK: - Embedding Providers

    @ViewBuilder
    private var embeddingProvidersList: some View {
        if embeddingProviders.isEmpty {
            ContentUnavailableView {
                Label("No Embedding Providers", systemImage: "arrow.triangle.2.circlepath")
            } description: {
                Text("Add an embedding provider to enable RAG mode in projects.")
            } actions: {
                Button("Add Provider") {
                    addEmbeddingProvider()
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            List(selection: $selectedEmbeddingProviderID) {
                ForEach(embeddingProviders) { provider in
                    NavigationLink(value: provider.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.body)
                                Text(EmbeddingProviderType(rawValue: provider.typeRaw)?.displayName ?? provider.typeRaw)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle()
                                .fill(provider.isEnabled ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteEmbeddingProvider(provider)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay(alignment: .bottom) {
                HStack(spacing: JinSpacing.small) {
                    Button {
                        addEmbeddingProvider()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add Embedding Provider")
                    Spacer()
                }
                .padding(JinSpacing.medium)
                .background(JinSemanticColor.panelSurface)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(JinSemanticColor.separator.opacity(0.45))
                        .frame(height: JinStrokeWidth.hairline)
                }
            }
        }
    }

    // MARK: - Rerank Providers

    @ViewBuilder
    private var rerankProvidersList: some View {
        if rerankProviders.isEmpty {
            ContentUnavailableView {
                Label("No Rerank Providers", systemImage: "arrow.up.arrow.down")
            } description: {
                Text("Add a rerank provider to improve RAG retrieval quality.")
            } actions: {
                Button("Add Provider") {
                    addRerankProvider()
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            List(selection: $selectedRerankProviderID) {
                ForEach(rerankProviders) { provider in
                    NavigationLink(value: provider.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.body)
                                Text(RerankProviderType(rawValue: provider.typeRaw)?.displayName ?? provider.typeRaw)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle()
                                .fill(provider.isEnabled ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteRerankProvider(provider)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay(alignment: .bottom) {
                HStack(spacing: JinSpacing.small) {
                    Button {
                        addRerankProvider()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add Rerank Provider")
                    Spacer()
                }
                .padding(JinSpacing.medium)
                .background(JinSemanticColor.panelSurface)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(JinSemanticColor.separator.opacity(0.45))
                        .frame(height: JinStrokeWidth.hairline)
                }
            }
        }
    }

    // MARK: - Actions

    private func addEmbeddingProvider() {
        let provider = EmbeddingProviderConfigEntity(
            name: "New Embedding Provider",
            typeRaw: EmbeddingProviderType.openai.rawValue
        )
        modelContext.insert(provider)
        try? modelContext.save()
        selectedEmbeddingProviderID = provider.id
    }

    private func deleteEmbeddingProvider(_ provider: EmbeddingProviderConfigEntity) {
        if selectedEmbeddingProviderID == provider.id {
            selectedEmbeddingProviderID = nil
        }
        modelContext.delete(provider)
        try? modelContext.save()
    }

    private func addRerankProvider() {
        let provider = RerankProviderConfigEntity(
            name: "New Rerank Provider",
            typeRaw: RerankProviderType.cohere.rawValue
        )
        modelContext.insert(provider)
        try? modelContext.save()
        selectedRerankProviderID = provider.id
    }

    private func deleteRerankProvider(_ provider: RerankProviderConfigEntity) {
        if selectedRerankProviderID == provider.id {
            selectedRerankProviderID = nil
        }
        modelContext.delete(provider)
        try? modelContext.save()
    }
}

// MARK: - Embedding Provider Detail Form

struct EmbeddingProviderDetailView: View {
    @Bindable var provider: EmbeddingProviderConfigEntity
    @Environment(\.modelContext) private var modelContext
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var showingValidation = false

    var body: some View {
        Form {
            Section("Provider") {
                LabeledContent("Name") {
                    TextField(text: nameBinding, prompt: Text("e.g., My OpenAI")) {
                        EmptyView()
                    }
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Type") {
                    Picker("", selection: typeBinding) {
                        ForEach(EmbeddingProviderType.allCases, id: \.rawValue) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                }

                Toggle("Enabled", isOn: enabledBinding)
            }

            Section("Authentication") {
                LabeledContent("API Key") {
                    SecureField(text: apiKeyBinding, prompt: Text("sk-...")) {
                        EmptyView()
                    }
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                }

                if resolvedType == .openaiCompatible {
                    LabeledContent("Base URL") {
                        TextField(text: baseURLBinding, prompt: Text("https://api.example.com")) {
                            EmptyView()
                        }
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    }
                }

                Button {
                    validateAPIKey()
                } label: {
                    HStack(spacing: 4) {
                        if isValidating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isValidating ? "Validating…" : "Test Connection")
                    }
                }
                .disabled(isValidating || (provider.apiKey ?? "").isEmpty)
            }

            Section("Model") {
                LabeledContent("Default Model") {
                    TextField(text: modelIDBinding, prompt: Text("e.g., text-embedding-3-small")) {
                        EmptyView()
                    }
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Connection Test", isPresented: $showingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var resolvedType: EmbeddingProviderType {
        EmbeddingProviderType(rawValue: provider.typeRaw) ?? .openai
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { provider.name },
            set: { newValue in
                provider.name = newValue
                try? modelContext.save()
            }
        )
    }

    private var typeBinding: Binding<EmbeddingProviderType> {
        Binding(
            get: { resolvedType },
            set: { newValue in
                provider.typeRaw = newValue.rawValue
                if provider.baseURL == nil || provider.baseURL?.isEmpty == true {
                    provider.baseURL = newValue.defaultBaseURL
                }
                try? modelContext.save()
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { provider.isEnabled },
            set: { newValue in
                provider.isEnabled = newValue
                try? modelContext.save()
            }
        )
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { provider.apiKey ?? "" },
            set: { newValue in
                provider.apiKey = newValue.isEmpty ? nil : newValue
                try? modelContext.save()
            }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { provider.baseURL ?? "" },
            set: { newValue in
                provider.baseURL = newValue.isEmpty ? nil : newValue
                try? modelContext.save()
            }
        )
    }

    private var modelIDBinding: Binding<String> {
        Binding(
            get: { provider.defaultModelID ?? "" },
            set: { newValue in
                provider.defaultModelID = newValue.isEmpty ? nil : newValue
                try? modelContext.save()
            }
        )
    }

    private func validateAPIKey() {
        guard let apiKey = provider.apiKey, !apiKey.isEmpty else { return }
        isValidating = true

        Task {
            do {
                let manager = EmbeddingProviderManager()
                let adapter = try await manager.createAdapter(for: provider)
                let isValid = try await adapter.validateAPIKey(apiKey)

                await MainActor.run {
                    isValidating = false
                    validationMessage = isValid ? "Connection successful." : "API key validation failed."
                    showingValidation = true
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    validationMessage = "Connection failed: \(error.localizedDescription)"
                    showingValidation = true
                }
            }
        }
    }
}

// MARK: - Rerank Provider Detail Form

struct RerankProviderDetailView: View {
    @Bindable var provider: RerankProviderConfigEntity
    @Environment(\.modelContext) private var modelContext
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var showingValidation = false

    var body: some View {
        Form {
            Section("Provider") {
                LabeledContent("Name") {
                    TextField(text: nameBinding, prompt: Text("e.g., Cohere Rerank")) {
                        EmptyView()
                    }
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Type") {
                    Picker("", selection: typeBinding) {
                        ForEach(RerankProviderType.allCases, id: \.rawValue) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                }

                Toggle("Enabled", isOn: enabledBinding)
            }

            Section("Authentication") {
                LabeledContent("API Key") {
                    SecureField(text: apiKeyBinding, prompt: Text("sk-...")) {
                        EmptyView()
                    }
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                }

                Button {
                    validateAPIKey()
                } label: {
                    HStack(spacing: 4) {
                        if isValidating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isValidating ? "Validating…" : "Test Connection")
                    }
                }
                .disabled(isValidating || (provider.apiKey ?? "").isEmpty)
            }

            Section("Model") {
                LabeledContent("Default Model") {
                    TextField(text: modelIDBinding, prompt: Text("e.g., rerank-v3.5")) {
                        EmptyView()
                    }
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Connection Test", isPresented: $showingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { provider.name },
            set: { newValue in
                provider.name = newValue
                try? modelContext.save()
            }
        )
    }

    private var typeBinding: Binding<RerankProviderType> {
        Binding(
            get: { RerankProviderType(rawValue: provider.typeRaw) ?? .cohere },
            set: { newValue in
                provider.typeRaw = newValue.rawValue
                try? modelContext.save()
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { provider.isEnabled },
            set: { newValue in
                provider.isEnabled = newValue
                try? modelContext.save()
            }
        )
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { provider.apiKey ?? "" },
            set: { newValue in
                provider.apiKey = newValue.isEmpty ? nil : newValue
                try? modelContext.save()
            }
        )
    }

    private var modelIDBinding: Binding<String> {
        Binding(
            get: { provider.defaultModelID ?? "" },
            set: { newValue in
                provider.defaultModelID = newValue.isEmpty ? nil : newValue
                try? modelContext.save()
            }
        )
    }

    private func validateAPIKey() {
        guard let apiKey = provider.apiKey, !apiKey.isEmpty else { return }
        isValidating = true

        Task {
            do {
                let manager = RerankProviderManager()
                let adapter = try await manager.createAdapter(for: provider)
                let isValid = try await adapter.validateAPIKey(apiKey)

                await MainActor.run {
                    isValidating = false
                    validationMessage = isValid ? "Connection successful." : "API key validation failed."
                    showingValidation = true
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    validationMessage = "Connection failed: \(error.localizedDescription)"
                    showingValidation = true
                }
            }
        }
    }
}
