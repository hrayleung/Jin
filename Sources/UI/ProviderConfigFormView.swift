import Collections
import SwiftUI
import SwiftData

struct ProviderConfigFormView: View {
    @Bindable var provider: ProviderConfigEntity
    @Environment(\.modelContext) var modelContext
    @Environment(\.openURL) var openURL
    @ObservedObject var codexServerController = CodexAppServerController.shared
    @State var apiKey = ""
    @State var serviceAccountJSON = ""
    @State var codexAuthMode: CodexAuthMode = .apiKey
    @State var codexAuthStatus: CodexAuthStatus = .idle
    @State var codexAccount: CodexAppServerAdapter.AccountStatus?
    @State var codexRateLimit: CodexAppServerAdapter.RateLimitStatus?
    @State var codexPendingLoginID: String?
    @State var codexAuthTask: Task<Void, Never>?
    @State var codexServerLaunchError: String?
    @State var codexWorkingDirectoryPresets: [CodexWorkingDirectoryPreset] = []
    @State var codexWorkingDirectoryPresetsDraft: [CodexWorkingDirectoryPreset] = []
    @State var showingCodexWorkingDirectoryPresetsSheet = false
    @State var showingAPIKey = false
    @State var hasLoadedCredentials = false
    @State var credentialSaveError: String?
    @State var credentialSaveTask: Task<Void, Never>?
    @State var testStatus: TestStatus = .idle
    @State var isFetchingModels = false
    @State var modelsError: String?
    @State var showingAddModel = false
    @State var showingDeleteAllModelsConfirmation = false
    @State var showingDeleteModelConfirmation = false
    @State var showingKeepFullySupportedModelsConfirmation = false
    @State var showingKeepEnabledModelsConfirmation = false
    @State var fetchedModelsForSelection: FetchedModelsSelectionState?
    @State var modelSearchText = ""
    @State var editingModel: ModelInfo?
    @State var modelPendingDeletion: ModelInfo?
    @State var hoveredModelID: String?
    @State var openRouterUsageStatus: OpenRouterUsageStatus = .idle
    @State var openRouterUsage: OpenRouterKeyUsage?
    @State var openRouterUsageTask: Task<Void, Never>?
    @State var claudeManagedRefreshTask: Task<Void, Never>?
    @State var claudeManagedAgents: [ClaudeManagedAgentDescriptor] = []
    @State var claudeManagedEnvironments: [ClaudeManagedEnvironmentDescriptor] = []
    @State var isRefreshingClaudeManagedResources = false
    @State var claudeManagedResourceError: String?
    @State var claudeManagedAgentIDDraft = ""
    @State var claudeManagedEnvironmentIDDraft = ""

    let providerManager = ProviderManager()
    let networkManager = NetworkManager()

    struct FetchedModelsSelectionState: Identifiable {
        let id = UUID()
        let models: [ModelInfo]
    }

    @ViewBuilder
    private var modelsSection: some View {
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
                     .anthropic, .claudeManagedAgents, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai,
                     .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .opencodeGo, .gemini:
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

            if providerType == .claudeManagedAgents {
                Section("Managed Defaults") {
                    claudeManagedDefaultsSection
                }
            } else {
                Section("Models") {
                    modelsSection
                }
                .animation(.easeInOut(duration: 0.18), value: filteredModels.count)
                .animation(.easeInOut(duration: 0.18), value: modelSearchText)
            }
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
            if providerType == .claudeManagedAgents {
                await MainActor.run {
                    syncClaudeManagedDefaultDrafts()
                }
                await refreshClaudeManagedResources()
            }
        }
        .onChange(of: apiKey) { _, _ in
            guard hasLoadedCredentials else { return }
            scheduleCredentialSave()
            if providerType == .openrouter {
                scheduleOpenRouterUsageRefresh()
            }
            if providerType == .claudeManagedAgents {
                scheduleClaudeManagedResourcesRefresh()
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
            claudeManagedRefreshTask?.cancel()
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
                Text("This will delete the model \u{201C}\(modelPendingDeletion.name)\u{201D} (\(modelPendingDeletion.id)).")
            } else {
                Text("This will remove this model from the local model list.")
            }
        }
    }

    var providerType: ProviderType? {
        ProviderType(rawValue: provider.typeRaw)
    }

    func baseURLBinding(defaultBaseURL: String) -> Binding<String> {
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
