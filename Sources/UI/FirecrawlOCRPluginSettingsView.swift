import SwiftUI

struct FirecrawlOCRPluginSettingsView: View {
    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var statusMessage: String?
    @State private var hasLoadedKey = false
    @State private var lastPersistedAPIKey = ""
    @State private var autoSaveTask: Task<Void, Never>?

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasConfiguredKey: Bool {
        !trimmedAPIKey.isEmpty || !lastPersistedAPIKey.isEmpty
    }

    var body: some View {
        JinSettingsPage(maxWidth: 620) {
            JinSettingsSection(
                "Shared Firecrawl API Key",
                detail: "Used by Firecrawl OCR and the Web Search plugin."
            ) {
                JinSettingsSecureFieldRow(
                    "API Key",
                    text: $apiKey,
                    isRevealed: $isKeyVisible,
                    usesMonospacedFont: true,
                    revealHelp: "Show API key",
                    concealHelp: "Hide API key"
                )

                HStack(spacing: JinSpacing.medium) {
                    Button("Clear", role: .destructive) {
                        clearKey()
                    }
                    .disabled(!hasConfiguredKey)

                    Spacer()
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            r2RequirementCallout
        }
        .navigationTitle("Firecrawl OCR")
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

    private var r2RequirementCallout: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.medium) {
            Text("Requires Cloudflare R2 to be configured for uploads.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: JinSpacing.small)

            Button("Configure R2 Upload…") {
                NotificationCenter.default.post(
                    name: .settingsNavigateToPlugin,
                    object: nil,
                    userInfo: [SettingsNavigationUserInfoKey.pluginID: "cloudflare_r2_upload"]
                )
            }
            .buttonStyle(.link)
        }
    }

    private func loadExistingKey() async {
        let existing = UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey) ?? ""
        await MainActor.run {
            apiKey = existing
            lastPersistedAPIKey = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func clearKey() {
        autoSaveTask?.cancel()
        lastPersistedAPIKey = ""
        apiKey = ""
        UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)
        statusMessage = "Cleared."
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
            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)
        } else {
            UserDefaults.standard.set(key, forKey: AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)
        }
        lastPersistedAPIKey = key
        statusMessage = key.isEmpty ? "Cleared." : nil
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }
}
