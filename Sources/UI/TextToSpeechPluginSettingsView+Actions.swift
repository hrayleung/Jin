import SwiftUI
import AVFoundation

// MARK: - API Key Persistence, Test Connection, Model & Voice Loading

extension TextToSpeechPluginSettingsView {

    func loadExistingKeyAndMaybeProviderResources() async {
        let requestedProviderRaw = await MainActor.run { providerRaw }
        await loadExistingKey()

        guard let load = await MainActor.run(body: {
            textToSpeechLoadSnapshot(matchingProviderRaw: requestedProviderRaw)
        }) else { return }

        guard !load.apiKey.isEmpty else {
            await MainActor.run {
                guard isCurrentTextToSpeechLoad(
                    provider: load.provider,
                    providerRaw: load.providerRaw,
                    apiKey: load.apiKey
                ) else { return }
                clearFetchedTextToSpeechModels()
            }
            return
        }

        switch load.provider {
        case .openai, .groq, .xiaomiMiMo:
            await loadRemoteTextToSpeechModels()
            await MainActor.run {
                guard isCurrentTextToSpeechLoad(
                    provider: load.provider,
                    providerRaw: load.providerRaw,
                    apiKey: load.apiKey
                ) else { return }
                clearFetchedTextToSpeechModels(for: .elevenlabs)
            }
        case .elevenlabs:
            await loadElevenLabsVoicesAndModels()
        case .whisperKit:
            await MainActor.run {
                guard isCurrentTextToSpeechLoad(
                    provider: load.provider,
                    providerRaw: load.providerRaw,
                    apiKey: load.apiKey
                ) else { return }
                clearFetchedTextToSpeechModels()
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
        clearFetchedTextToSpeechModels(for: provider)
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
            statusMessage = providerErrorMessage(for: rawValue)
            statusIsError = true
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
        guard let resolved = TextToSpeechProvider(rawValue: rawValue) else { return nil }
        switch resolved {
        case .elevenlabs:
            return AppPreferenceKeys.ttsElevenLabsAPIKey
        case .openai:
            return AppPreferenceKeys.ttsOpenAIAPIKey
        case .groq:
            return AppPreferenceKeys.ttsGroqAPIKey
        case .xiaomiMiMo:
            return AppPreferenceKeys.ttsMiMoAPIKey
        case .whisperKit:
            return nil
        }
    }

    func providerErrorMessage(for rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return SpeechExtensionError.textToSpeechProviderNotConfigured.localizedDescription
        }
        return SpeechExtensionError.invalidTextToSpeechProvider(trimmed).localizedDescription
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
                case .xiaomiMiMo:
                    let base = URL(string: miMoBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? MiMoAudioClient.Constants.defaultBaseURL
                    let client = MiMoAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                    try await client.validateAPIKey()
                case .elevenlabs:
                    let base = URL(string: elevenLabsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ElevenLabsTTSClient.Constants.defaultBaseURL
                    let client = ElevenLabsTTSClient(apiKey: trimmedAPIKey, baseURL: base)
                    let voices = try await client.listVoices()

                    let selectedVoice = elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let voiceIdToTest = !selectedVoice.isEmpty ? selectedVoice : (voices.first?.voiceId ?? "")
                    guard !voiceIdToTest.isEmpty else {
                        throw SpeechExtensionError.missingElevenLabsVoice
                    }

                    let voiceSettings = ElevenLabsTTSClient.VoiceSettings(
                        stability: elevenLabsStability,
                        similarityBoost: elevenLabsSimilarityBoost,
                        style: elevenLabsStyle,
                        useSpeakerBoost: elevenLabsUseSpeakerBoost
                    )

                    // Validate that this key can actually synthesize audio (keys may be scope-restricted per endpoint).
                    _ = try await client.createSpeech(
                        text: "Hello from Jin.",
                        voiceId: voiceIdToTest,
                        modelId: elevenLabsModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : elevenLabsModelID,
                        outputFormat: elevenLabsOutputFormat,
                        optimizeStreamingLatency: elevenLabsOptimizeStreamingLatency,
                        enableLogging: elevenLabsEnableLogging,
                        voiceSettings: voiceSettings
                    )
                case .whisperKit:
                    return
                }

                await MainActor.run {
                    isTesting = false
                    statusMessage = JinSettingsStatusText.connectionVerifiedMessage
                    statusIsError = false
                }

                switch provider {
                case .openai, .groq, .xiaomiMiMo:
                    await loadRemoteTextToSpeechModels(updateStatus: false)
                case .elevenlabs:
                    await loadElevenLabsVoicesAndModels(updateStatus: false)
                case .whisperKit:
                    break
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    if let llmError = error as? LLMError, case .authenticationFailed = llmError {
                        statusMessage = "\(llmError.localizedDescription)\n\nIf your ElevenLabs key uses endpoint scopes, enable access to /v1/text-to-speech."
                    } else {
                        statusMessage = error.localizedDescription
                    }
                    statusIsError = true
                }
            }
        }
    }
    func loadRemoteTextToSpeechModels(updateStatus: Bool = true) async {
        guard let load = await MainActor.run(body: { textToSpeechLoadSnapshot() }) else { return }
        guard !load.apiKey.isEmpty else { return }
        guard load.provider == .openai || load.provider == .groq || load.provider == .xiaomiMiMo else { return }

        await MainActor.run {
            guard isCurrentTextToSpeechLoad(
                provider: load.provider,
                providerRaw: load.providerRaw,
                apiKey: load.apiKey
            ) else { return }
            isLoadingModels = true
        }

        do {
            let availableModels: [SpeechProviderModelChoice]
            switch load.provider {
            case .openai:
                let base = URL(string: openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? OpenAIAudioClient.Constants.defaultBaseURL
                let client = OpenAIAudioClient(apiKey: load.apiKey, baseURL: base)
                availableModels = try await client.listModels()
            case .groq:
                let base = URL(string: groqBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? GroqAudioClient.Constants.defaultBaseURL
                let client = GroqAudioClient(apiKey: load.apiKey, baseURL: base)
                availableModels = try await client.listModels()
            case .xiaomiMiMo:
                let base = URL(string: miMoBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                    ?? MiMoAudioClient.Constants.defaultBaseURL
                let client = MiMoAudioClient(apiKey: load.apiKey, baseURL: base)
                availableModels = try await client.listModels()
            case .elevenlabs, .whisperKit:
                return
            }

            let filteredModels = SpeechProviderModelCatalog.textToSpeechChoices(
                for: load.provider,
                availableModels: availableModels
            )

            await MainActor.run {
                guard isCurrentTextToSpeechLoad(
                    provider: load.provider,
                    providerRaw: load.providerRaw,
                    apiKey: load.apiKey
                ) else { return }
                setFetchedTextToSpeechModels(filteredModels, for: load.provider)
                normalizeTextToSpeechModelSelectionIfNeeded(for: load.provider, using: filteredModels)
                isLoadingModels = false
            }
        } catch {
            await MainActor.run {
                guard isCurrentTextToSpeechLoad(
                    provider: load.provider,
                    providerRaw: load.providerRaw,
                    apiKey: load.apiKey
                ) else { return }
                clearFetchedTextToSpeechModels(for: load.provider)
                if updateStatus {
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    func loadElevenLabsVoicesAndModels(updateStatus: Bool = true) async {
        guard let load = await MainActor.run(body: { textToSpeechLoadSnapshot() }) else { return }
        guard load.provider == .elevenlabs else { return }
        guard !load.apiKey.isEmpty else { return }

        await MainActor.run {
            guard isCurrentTextToSpeechLoad(
                provider: load.provider,
                providerRaw: load.providerRaw,
                apiKey: load.apiKey
            ) else { return }
            isLoadingVoices = true
        }

        let base = URL(string: elevenLabsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ElevenLabsTTSClient.Constants.defaultBaseURL
        let client = ElevenLabsTTSClient(apiKey: load.apiKey, baseURL: base)

        // Fetch voices (required) and models (optional) independently so a
        // scoped key without models_read permission still loads voices.
        var voices: [ElevenLabsTTSClient.Voice] = []
        var models: [ElevenLabsTTSClient.Model] = []

        do {
            voices = try await client.listVoices()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            await MainActor.run {
                guard isCurrentTextToSpeechLoad(
                    provider: load.provider,
                    providerRaw: load.providerRaw,
                    apiKey: load.apiKey
                ) else { return }
                isLoadingVoices = false
                if updateStatus {
                    elevenLabsVoices = []
                    elevenLabsModels = []
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
            return
        }

        // Model fetch is best-effort; failure leaves the manual text field visible.
        do {
            models = try await client.listModels()
                .filter { $0.canDoTextToSpeech }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            // Silently fall back to empty models list (manual input).
        }

        await MainActor.run {
            guard isCurrentTextToSpeechLoad(
                provider: load.provider,
                providerRaw: load.providerRaw,
                apiKey: load.apiKey
            ) else { return }
            elevenLabsVoices = voices
            elevenLabsModels = models

            if elevenLabsVoiceID.isEmpty {
                elevenLabsVoiceID = voices.first?.voiceId ?? ""
            } else if !voices.contains(where: { $0.voiceId == elevenLabsVoiceID }) {
                elevenLabsVoiceID = voices.first?.voiceId ?? ""
            }

            if !models.isEmpty {
                let currentModel = elevenLabsModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                if currentModel.isEmpty {
                    elevenLabsModelID = models.first?.modelId ?? ""
                }
            }

            isLoadingVoices = false
        }
    }

    @MainActor
    func textToSpeechLoadSnapshot(
        matchingProviderRaw expectedProviderRaw: String? = nil
    ) -> (provider: TextToSpeechProvider, providerRaw: String, apiKey: String)? {
        guard !Task.isCancelled else { return nil }
        guard expectedProviderRaw == nil || providerRaw == expectedProviderRaw else { return nil }
        guard let provider else { return nil }
        return (provider, providerRaw, trimmedAPIKey)
    }

    @MainActor
    func isCurrentTextToSpeechLoad(
        provider: TextToSpeechProvider,
        providerRaw: String,
        apiKey: String
    ) -> Bool {
        !Task.isCancelled
            && self.provider == provider
            && self.providerRaw == providerRaw
            && trimmedAPIKey == apiKey
    }

    @MainActor
    func clearFetchedTextToSpeechModels(for provider: TextToSpeechProvider? = nil) {
        isLoadingModels = false
        isLoadingVoices = false

        switch provider {
        case .openai:
            openAIModels = []
        case .groq:
            groqModels = []
        case .xiaomiMiMo:
            miMoModels = []
        case .elevenlabs:
            elevenLabsVoices = []
            elevenLabsModels = []
            isPlayingVoicePreview = false
            voicePreviewPlayer?.stop()
            voicePreviewPlayer = nil
        case .whisperKit, .none:
            openAIModels = []
            groqModels = []
            miMoModels = []
            elevenLabsVoices = []
            elevenLabsModels = []
            isPlayingVoicePreview = false
            voicePreviewPlayer?.stop()
            voicePreviewPlayer = nil
        }
    }

    @MainActor
    func setFetchedTextToSpeechModels(_ models: [SpeechProviderModelChoice], for provider: TextToSpeechProvider) {
        switch provider {
        case .openai:
            openAIModels = models
        case .groq:
            groqModels = models
        case .xiaomiMiMo:
            miMoModels = models
        case .elevenlabs, .whisperKit:
            break
        }
    }

    @MainActor
    func normalizeTextToSpeechModelSelectionIfNeeded(
        for provider: TextToSpeechProvider,
        using models: [SpeechProviderModelChoice]
    ) {
        guard !models.isEmpty else { return }

        switch provider {
        case .openai:
            let currentModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty {
                openAIModel = models.first?.id ?? openAIModel
            }
        case .groq:
            let currentModel = groqModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty {
                let nextModel = models.first?.id ?? groqModel
                if nextModel != groqModel {
                    groqModel = nextModel
                    normalizeGroqVoiceIfNeeded()
                }
            }
        case .xiaomiMiMo:
            let currentModel = miMoModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty {
                miMoModel = models.first?.id ?? miMoModel
            }
            normalizeMiMoVoiceIfNeeded()
        case .elevenlabs, .whisperKit:
            break
        }
    }

    func playSelectedVoicePreview() async {
        guard let url = selectedElevenLabsVoicePreviewURL else { return }

        if isPlayingVoicePreview {
            await MainActor.run {
                voicePreviewPlayer?.stop()
                voicePreviewPlayer = nil
                isPlayingVoicePreview = false
            }
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, _) = try await NetworkDebugRequestExecutor.data(
                for: request,
                mode: "tts_voice_preview"
            )
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            await MainActor.run {
                voicePreviewPlayer = player
                isPlayingVoicePreview = true
            }
            player.play()

            // Poll completion state (AVAudioPlayer delegate requires NSObject conformance).
            Task { @MainActor in
                while player.isPlaying {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if voicePreviewPlayer === player {
                    voicePreviewPlayer = nil
                    isPlayingVoicePreview = false
                }
            }
        } catch {
            await MainActor.run {
                statusMessage = error.localizedDescription
                statusIsError = true
                isPlayingVoicePreview = false
            }
        }
    }
}
