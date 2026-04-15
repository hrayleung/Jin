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

    var body: some View {
        Form {
            Section("Shared Firecrawl API Key") {
                HStack(spacing: 8) {
                    Group {
                        if isKeyVisible {
                            TextField("API Key", text: $apiKey)
                                .textContentType(.password)
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textContentType(.password)
                        }
                    }

                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(isKeyVisible ? "Hide API key" : "Show API key")
                    .disabled(apiKey.isEmpty)
                }

                HStack(spacing: 12) {
                    Button("Clear", role: .destructive) { clearKey() }

                    Spacer()
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("This key is shared with the Web Search plugin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Requirements") {
                Text("Firecrawl OCR uploads local PDFs to your configured Cloudflare R2 public bucket before calling Firecrawl.")
                Text("Configure Cloudflare R2 in Settings → Plugins → Cloudflare R2 Upload.")
                Text("Choose Firecrawl parser mode per chat from the PDF menu: Fast, Auto, or OCR.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
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
