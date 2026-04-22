import SwiftUI

// MARK: - API Key Persistence, Test Connection & Model Loading

extension SpeechToTextPluginSettingsView {

    func loadExistingKeyAndMaybeModels() async {
        await loadExistingKey()

        guard let provider, !trimmedAPIKey.isEmpty else {
            await MainActor.run {
                clearFetchedSpeechToTextModels()
            }
            return
        }

        switch provider {
        case .openai, .groq, .mistral, .elevenlabs:
            await loadRemoteSpeechToTextModels()
        case .whisperKit:
            await MainActor.run {
                clearFetchedSpeechToTextModels()
            }
        }
    }

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
        clearFetchedSpeechToTextModels(for: provider)
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
        case .elevenlabs:
            return AppPreferenceKeys.sttElevenLabsAPIKey
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
                case .elevenlabs:
                    let base = URL(string: elevenLabsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ElevenLabsSTTClient.Constants.defaultBaseURL
                    let client = ElevenLabsSTTClient(apiKey: trimmedAPIKey, baseURL: base)
                    try await client.validateAPIKey()
                case .whisperKit:
                    return
                }

                await MainActor.run {
                    isTesting = false
                    statusMessage = "Connection OK."
                    statusIsError = false
                }

                switch provider {
                case .openai, .groq, .mistral, .elevenlabs:
                    await loadRemoteSpeechToTextModels(updateStatus: false)
                case .whisperKit:
                    break
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

    func loadRemoteSpeechToTextModels(updateStatus: Bool = true) async {
        guard let provider else { return }
        guard !trimmedAPIKey.isEmpty else { return }
        guard provider != .whisperKit else { return }

        await MainActor.run {
            isLoadingModels = true
        }

        do {
            let availableModels: [SpeechProviderModelChoice]
            switch provider {
            case .openai:
                let base = URL(string: openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? OpenAIAudioClient.Constants.defaultBaseURL
                let client = OpenAIAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                availableModels = try await client.listModels()
            case .groq:
                let base = URL(string: groqBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? GroqAudioClient.Constants.defaultBaseURL
                let client = GroqAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                availableModels = try await client.listModels()
            case .mistral:
                let defaultBase = URL(string: ProviderType.mistral.defaultBaseURL ?? "https://api.mistral.ai/v1")!
                let base = URL(string: mistralBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? defaultBase
                let client = OpenAIAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                availableModels = try await client.listModels()
            case .elevenlabs:
                let base = URL(string: elevenLabsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? ElevenLabsSTTClient.Constants.defaultBaseURL
                let client = ElevenLabsSTTClient(apiKey: trimmedAPIKey, baseURL: base)
                availableModels = try await client.listModels()
            case .whisperKit:
                return
            }

            let filteredModels = SpeechProviderModelCatalog.speechToTextChoices(
                for: provider,
                availableModels: availableModels
            )

            await MainActor.run {
                setFetchedSpeechToTextModels(filteredModels, for: provider)
                normalizeSpeechToTextModelSelectionIfNeeded(for: provider, using: filteredModels)
                isLoadingModels = false
            }
        } catch {
            await MainActor.run {
                clearFetchedSpeechToTextModels(for: provider)
                isLoadingModels = false
                if updateStatus {
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    @MainActor
    func clearFetchedSpeechToTextModels(for provider: SpeechToTextProvider? = nil) {
        switch provider {
        case .openai:
            openAIModels = []
        case .groq:
            groqModels = []
        case .mistral:
            mistralModels = []
        case .elevenlabs:
            elevenLabsModels = []
        case .whisperKit, .none:
            openAIModels = []
            groqModels = []
            mistralModels = []
            elevenLabsModels = []
        }
    }

    @MainActor
    func setFetchedSpeechToTextModels(_ models: [SpeechProviderModelChoice], for provider: SpeechToTextProvider) {
        switch provider {
        case .openai:
            openAIModels = models
        case .groq:
            groqModels = models
        case .mistral:
            mistralModels = models
        case .elevenlabs:
            elevenLabsModels = models
        case .whisperKit:
            break
        }
    }

    @MainActor
    func normalizeSpeechToTextModelSelectionIfNeeded(
        for provider: SpeechToTextProvider,
        using models: [SpeechProviderModelChoice]
    ) {
        guard !models.isEmpty else { return }

        switch provider {
        case .openai:
            let currentModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty || !models.contains(where: { $0.id == currentModel }) {
                openAIModel = models.first?.id ?? openAIModel
            }
        case .groq:
            let currentModel = groqModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty || !models.contains(where: { $0.id == currentModel }) {
                groqModel = models.first?.id ?? groqModel
            }
        case .mistral:
            let currentModel = mistralModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty || !models.contains(where: { $0.id == currentModel }) {
                mistralModel = models.first?.id ?? mistralModel
            }
        case .elevenlabs:
            let currentModel = elevenLabsModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty || !models.contains(where: { $0.id == currentModel }) {
                elevenLabsModel = models.first?.id ?? elevenLabsModel
            }
        case .whisperKit:
            break
        }
    }
}
