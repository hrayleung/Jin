import SwiftUI

struct PluginAPIKeySettingsView: View {
    let title: String
    let preferenceKey: String
    let apiKeyHint: String?
    let testConnection: (String) async throws -> Void

    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var hasLoadedKey = false
    @State private var lastPersistedAPIKey = ""
    @State private var autoSaveTask: Task<Void, Never>?

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        title: String,
        preferenceKey: String,
        apiKeyHint: String? = nil,
        testConnection: @escaping (String) async throws -> Void
    ) {
        self.title = title
        self.preferenceKey = preferenceKey
        self.apiKeyHint = apiKeyHint
        self.testConnection = testConnection
    }

    var body: some View {
        JinSettingsPage {
            JinSettingsSection(
                "API Key",
                detail: "Stored locally on this Mac and saved automatically as you type."
            ) {
                JinSettingsControlRow(
                    "API Key",
                    supportingText: "Stored locally on this Mac. Changes save automatically."
                ) {
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
                    JinSettingsStatusText(text: statusMessage, isError: statusIsError)
                }

                if let apiKeyHint, !apiKeyHint.isEmpty {
                    Text(apiKeyHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
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
        let existing = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
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
        UserDefaults.standard.removeObject(forKey: preferenceKey)
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
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        } else {
            UserDefaults.standard.set(key, forKey: preferenceKey)
        }
        lastPersistedAPIKey = key
        statusMessage = key.isEmpty ? "Cleared." : "Saved automatically."
        statusIsError = false
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    private func runTestConnection() {
        guard !trimmedAPIKey.isEmpty else { return }

        statusMessage = nil
        statusIsError = false
        isTesting = true

        Task {
            do {
                try await testConnection(trimmedAPIKey)
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
