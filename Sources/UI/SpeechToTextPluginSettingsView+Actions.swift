import SwiftUI

// MARK: - API Key Persistence & Test Connection

extension SpeechToTextPluginSettingsView {

    func loadExistingKey() async {
        if provider?.requiresAPIKey == false {
            await MainActor.run {
                apiKey = ""
                lastPersistedAPIKey = ""
                statusMessage = nil
                statusIsError = false
            }
            return
        }

        guard let preferenceKey = currentAPIKeyPreferenceKey else {
            await MainActor.run {
                apiKey = ""
                lastPersistedAPIKey = ""
                statusMessage = providerErrorMessage(for: providerRaw)
                statusIsError = true
            }
            return
        }

        let existing = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
        await MainActor.run {
            apiKey = existing
            lastPersistedAPIKey = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func clearKey() {
        autoSaveTask?.cancel()
        statusMessage = nil
        statusIsError = false

        guard provider?.requiresAPIKey != false,
              let preferenceKey = currentAPIKeyPreferenceKey else {
            return
        }

        UserDefaults.standard.removeObject(forKey: preferenceKey)
        lastPersistedAPIKey = ""
        apiKey = ""
        statusMessage = "Cleared."
        statusIsError = false
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    func scheduleAutoSave() {
        autoSaveTask?.cancel()

        guard provider?.requiresAPIKey != false else { return }

        let key = trimmedAPIKey
        guard let preferenceKey = currentAPIKeyPreferenceKey else {
            statusMessage = providerErrorMessage(for: providerRaw)
            statusIsError = true
            return
        }
        guard key != lastPersistedAPIKey else { return }

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistAPIKey(key, forPreferenceKey: preferenceKey, showSavedStatus: true)
            }
        }
    }

    func persistAPIKeyIfNeeded(forProviderRaw rawValue: String, showSavedStatus: Bool) {
        guard let preferenceKey = apiKeyPreferenceKey(for: rawValue) else {
            return
        }
        let key = trimmedAPIKey
        persistAPIKey(key, forPreferenceKey: preferenceKey, showSavedStatus: showSavedStatus)
    }

    func persistAPIKey(_ key: String, forPreferenceKey preferenceKey: String, showSavedStatus: Bool) {
        let isCurrentProvider = preferenceKey == currentAPIKeyPreferenceKey
        if isCurrentProvider, key == lastPersistedAPIKey {
            return
        }
        if !isCurrentProvider {
            let existing = (UserDefaults.standard.string(forKey: preferenceKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if existing == key {
                return
            }
        }

        if key.isEmpty {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        } else {
            UserDefaults.standard.set(key, forKey: preferenceKey)
        }

        if isCurrentProvider {
            lastPersistedAPIKey = key
            if showSavedStatus {
                statusMessage = key.isEmpty ? "Cleared." : "Saved automatically."
                statusIsError = false
            }
        }

        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    func apiKeyPreferenceKey(for rawValue: String) -> String? {
        guard let resolved = SpeechToTextProvider(rawValue: rawValue) else { return nil }
        switch resolved {
        case .openai:
            return AppPreferenceKeys.sttOpenAIAPIKey
        case .groq:
            return AppPreferenceKeys.sttGroqAPIKey
        case .mistral:
            return AppPreferenceKeys.sttMistralAPIKey
        case .whisperKit:
            return nil
        }
    }

    func providerErrorMessage(for rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return SpeechExtensionError.speechToTextProviderNotConfigured.localizedDescription
        }
        return SpeechExtensionError.invalidSpeechToTextProvider(trimmed).localizedDescription
    }

    func testConnection() {
        guard !trimmedAPIKey.isEmpty else { return }
        guard let provider, provider.requiresAPIKey else {
            statusMessage = providerErrorMessage(for: providerRaw)
            statusIsError = true
            return
        }

        statusMessage = nil
        statusIsError = false
        isTesting = true

        Task {
            do {
                switch provider {
                case .openai:
                    let base = URL(string: openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? OpenAIAudioClient.Constants.defaultBaseURL
                    let client = OpenAIAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                    try await client.validateAPIKey()
                case .groq:
                    let base = URL(string: groqBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? GroqAudioClient.Constants.defaultBaseURL
                    let client = GroqAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                    try await client.validateAPIKey()
                case .mistral:
                    let defaultBase = URL(string: ProviderType.mistral.defaultBaseURL ?? "https://api.mistral.ai/v1")!
                    let base = URL(string: mistralBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? defaultBase
                    let client = OpenAIAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                    try await client.validateAPIKey()
                case .whisperKit:
                    return
                }

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
