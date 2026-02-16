import SwiftUI

struct DeepSeekOCRPluginSettingsView: View {
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var hasLoadedKey = false
    @State private var lastPersistedAPIKey = ""
    @State private var autoSaveTask: Task<Void, Never>?

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section("DeepSeek OCR (DeepInfra)") {
                Text("Used to OCR PDFs via DeepInfra-hosted DeepSeek-OCR when your selected model does not support native PDF reading, or when you choose DeepSeek OCR in the chat composer.")
                    .jinInfoCallout()
            }

            Section("API Key") {
                SecureField("API Key", text: $apiKey)
                    .textContentType(.password)

                Text("Stored locally on this device and saved automatically while you type.")
                    .jinInfoCallout()

                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
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
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .navigationTitle("DeepSeek OCR")
        .task {
            await loadExistingKey()
            hasLoadedKey = true
        }
        .onChange(of: apiKey) { _, _ in
            guard hasLoadedKey else { return }
            scheduleAutoSave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
        }
    }

    private func loadExistingKey() async {
        let existing = UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey) ?? ""
        await MainActor.run {
            apiKey = existing
            lastPersistedAPIKey = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func clearKey() {
        autoSaveTask?.cancel()
        statusMessage = nil
        statusIsError = false

        lastPersistedAPIKey = ""
        apiKey = ""
        UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey)
        statusMessage = "Cleared."
        statusIsError = false
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
            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey)
        } else {
            UserDefaults.standard.set(key, forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey)
        }
        lastPersistedAPIKey = key
        statusMessage = key.isEmpty ? "Cleared." : "Saved automatically."
        statusIsError = false
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    private func testConnection() {
        guard !trimmedAPIKey.isEmpty else { return }

        statusMessage = nil
        statusIsError = false
        isTesting = true

        Task {
            do {
                let client = DeepInfraDeepSeekOCRClient(apiKey: trimmedAPIKey)
                try await client.validateAPIKey()
                await MainActor.run {
                    isTesting = false
                    statusMessage = "Connection OK."
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
}
