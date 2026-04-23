import SwiftUI

struct OpenRouterOCRPluginSettingsView: View {
    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var hasLoadedSettings = false
    @State private var lastPersistedAPIKey = ""
    @State private var lastPersistedModelID = OpenRouterOCRModelCatalog.defaultModelID
    @State private var selectedModelID = OpenRouterOCRModelCatalog.defaultModelID
    @State private var autoSaveTask: Task<Void, Never>?

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        JinSettingsPage(maxWidth: 620) {
            JinSettingsSection("Connection") {
                JinSettingsControlRow("API Key") {
                    JinRevealableSecureField(
                        title: "API Key",
                        text: $apiKey,
                        isRevealed: $isKeyVisible,
                        revealHelp: "Show API key",
                        concealHelp: "Hide API key"
                    )
                }

                HStack(spacing: JinSpacing.medium) {
                    Button("Test Connection") { runTestConnection() }
                        .disabled(trimmedAPIKey.isEmpty || isTesting)

                    Button("Clear", role: .destructive) { clearKey() }
                        .disabled(isTesting)

                    Spacer()

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let statusMessage {
                    JinSettingsStatusText(
                        text: statusMessage,
                        isError: statusIsError,
                        isSuccess: isConnectionVerifiedStatus(statusMessage)
                    )
                }
            }

            JinSettingsSection("OCR Model") {
                JinSettingsControlRow("Model") {
                    Picker("Model", selection: $selectedModelID) {
                        ForEach(OpenRouterOCRModelCatalog.entries) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
        .navigationTitle("OpenRouter OCR")
        .task {
            await loadExistingSettings()
            hasLoadedSettings = true
        }
        .onChange(of: apiKey) { _, _ in
            guard hasLoadedSettings else { return }
            scheduleAutoSave()
        }
        .onChange(of: selectedModelID) { _, newValue in
            guard hasLoadedSettings else { return }
            persistModelID(newValue)
        }
        .onDisappear {
            autoSaveTask?.cancel()
        }
    }

    private func loadExistingSettings() async {
        let defaults = UserDefaults.standard
        let existingKey = defaults.string(forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey) ?? ""
        let storedModelID = defaults.string(forKey: AppPreferenceKeys.pluginOpenRouterOCRModelID)
        let existingModelID = OpenRouterOCRModelCatalog.normalizedModelID(storedModelID)

        await MainActor.run {
            apiKey = existingKey
            selectedModelID = existingModelID
            lastPersistedAPIKey = existingKey.trimmingCharacters(in: .whitespacesAndNewlines)
            lastPersistedModelID = existingModelID
        }

        if storedModelID != existingModelID {
            defaults.set(existingModelID, forKey: AppPreferenceKeys.pluginOpenRouterOCRModelID)
            NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
        }
    }

    private func clearKey() {
        autoSaveTask?.cancel()
        statusMessage = nil
        statusIsError = false
        lastPersistedAPIKey = ""
        apiKey = ""
        UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey)
        statusMessage = "Cleared"
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        let key = trimmedAPIKey
        guard key != lastPersistedAPIKey else { return }

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistAPIKey(key)
            }
        }
    }

    private func persistAPIKey(_ key: String) {
        guard key != lastPersistedAPIKey else { return }

        if key.isEmpty {
            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey)
        } else {
            UserDefaults.standard.set(key, forKey: AppPreferenceKeys.pluginOpenRouterOCRAPIKey)
        }
        lastPersistedAPIKey = key
        statusMessage = key.isEmpty ? "Cleared" : nil
        statusIsError = false
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    private func persistModelID(_ modelID: String) {
        let normalized = OpenRouterOCRModelCatalog.normalizedModelID(modelID)
        guard normalized != lastPersistedModelID else {
            if selectedModelID != normalized {
                selectedModelID = normalized
            }
            return
        }

        if selectedModelID != normalized {
            selectedModelID = normalized
        }
        UserDefaults.standard.set(normalized, forKey: AppPreferenceKeys.pluginOpenRouterOCRModelID)
        lastPersistedModelID = normalized
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    private func runTestConnection() {
        guard !trimmedAPIKey.isEmpty else { return }

        statusMessage = nil
        statusIsError = false
        isTesting = true

        let apiKey = trimmedAPIKey
        let modelID = OpenRouterOCRModelCatalog.normalizedModelID(selectedModelID)
        Task {
            do {
                let client = OpenRouterOCRClient(apiKey: apiKey, modelID: modelID)
                try await client.validateAPIKey()
                await MainActor.run {
                    isTesting = false
                    statusMessage = "Connection verified."
                    statusIsError = false
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    private func isConnectionVerifiedStatus(_ message: String) -> Bool {
        !statusIsError && message == "Connection verified."
    }
}
