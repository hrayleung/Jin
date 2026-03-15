import SwiftUI
import AVFoundation

// MARK: - API Key Persistence, Test Connection & Voice Loading

extension TextToSpeechPluginSettingsView {

    func loadExistingKeyAndMaybeVoices() async {
        await loadExistingKey()
        if provider == .elevenlabs, !trimmedAPIKey.isEmpty {
            await loadElevenLabsVoices()
        } else {
            await MainActor.run {
                elevenLabsVoices = []
                isPlayingVoicePreview = false
                voicePreviewPlayer?.stop()
                voicePreviewPlayer = nil
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
        elevenLabsVoices = []
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
                    statusMessage = "Connection OK."
                    statusIsError = false
                }

                if provider == .elevenlabs {
                    await loadElevenLabsVoices()
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

    func loadElevenLabsVoices() async {
        guard provider == .elevenlabs else { return }
        guard !trimmedAPIKey.isEmpty else { return }

        await MainActor.run {
            isLoadingVoices = true
        }

        do {
            let base = URL(string: elevenLabsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ElevenLabsTTSClient.Constants.defaultBaseURL
            let client = ElevenLabsTTSClient(apiKey: trimmedAPIKey, baseURL: base)
            let voices = try await client.listVoices()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await MainActor.run {
                elevenLabsVoices = voices
                if elevenLabsVoiceID.isEmpty {
                    elevenLabsVoiceID = voices.first?.voiceId ?? ""
                } else if !voices.contains(where: { $0.voiceId == elevenLabsVoiceID }) {
                    elevenLabsVoiceID = voices.first?.voiceId ?? ""
                }
                isLoadingVoices = false
            }
        } catch {
            await MainActor.run {
                elevenLabsVoices = []
                isLoadingVoices = false
                statusMessage = error.localizedDescription
                statusIsError = true
            }
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
