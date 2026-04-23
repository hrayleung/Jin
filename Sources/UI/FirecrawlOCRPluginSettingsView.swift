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
                detail: "This key is used by Firecrawl OCR and the Web Search plugin."
            ) {
                JinSettingsControlRow(
                    "API Key",
                    supportingText: "Changes save automatically."
                ) {
                    apiKeyField
                }

                HStack(spacing: JinSpacing.medium) {
                    Button("Clear", role: .destructive) {
                        clearKey()
                    }
                    .disabled(!hasConfiguredKey)

                    Spacer()
                }

                Text(statusMessage ?? "Shared with Web Search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            JinSettingsSection(
                "Before You Use Firecrawl OCR",
                detail: "Firecrawl OCR needs one shared API key and a configured Cloudflare R2 upload target.",
                style: .plain
            ) {
                guidanceSection
            }
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

    private var apiKeyField: some View {
        JinRevealableSecureField(
            title: "API Key",
            text: $apiKey,
            isRevealed: $isKeyVisible,
            usesMonospacedFont: true,
            revealHelp: "Show API key",
            concealHelp: "Hide API key"
        )
    }

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            guidanceRow(
                title: "Cloudflare R2 is required",
                detail: "Firecrawl OCR uploads each local PDF to your configured public R2 bucket before calling Firecrawl.",
                systemImage: "externaldrive.badge.icloud"
            )

            Divider()

            guidanceRow(
                title: "Configure the upload target first",
                detail: "Open Settings → Plugins → Cloudflare R2 Upload and add your bucket details there.",
                systemImage: "gearshape.2"
            )

            Divider()

            guidanceRow(
                title: "Choose a parser per chat",
                detail: "Use the PDF menu to switch between Fast, Auto, and OCR for each conversation.",
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    private func guidanceRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: JinSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        statusMessage = key.isEmpty ? "Cleared." : "Saved automatically."
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }
}
