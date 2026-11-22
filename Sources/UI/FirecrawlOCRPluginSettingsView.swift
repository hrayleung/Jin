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
        JinSettingsPage(title: "Firecrawl OCR") {
            JinSettingsSection("Connection") {
                JinSettingsSecureFieldRow(
                    "API Key",
                    prompt: "Paste API key",
                    supportingText: "Shared with the Web Search plugin.",
                    text: $apiKey,
                    isRevealed: $isKeyVisible,
                    revealHelp: "Show API key",
                    concealHelp: "Hide API key"
                )

                HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                    if let statusMessage {
                        JinSettingsStatusText(text: statusMessage)
                    }

                    Spacer(minLength: 0)

                    Button("Clear", role: .destructive) {
                        clearKey()
                    }
                    .controlSize(.small)
                    .disabled(!hasConfiguredKey)
                }
            }

            r2RequirementSection
        }
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
            if hasLoadedKey { persistAPIKey(trimmedAPIKey) }
        }
    }

    private var r2RequirementSection: some View {
        JinSettingsSection("Requirements") {
            JinSettingsControlRow(
                "Cloudflare R2 Upload",
                supportingText: "PDFs are uploaded to R2 so Firecrawl can read them. Enable and configure it first."
            ) {
                Button("Open Settings…") {
                    NotificationCenter.default.post(
                        name: .settingsNavigateToPlugin,
                        object: nil,
                        userInfo: [SettingsNavigationUserInfoKey.pluginID: "cloudflare_r2_upload"]
                    )
                }
                .controlSize(.small)
            }
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

        autoSaveTask = PluginAutosave.schedule {
            persistAPIKey(key)
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
