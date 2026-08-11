import Foundation

// MARK: - Connection Testing

extension TextToSpeechPluginSettingsView {

    func testConnection() {
        guard !trimmedAPIKey.isEmpty else { return }
        guard let provider else {
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
                case .openai, .openRouter, .groq, .mistral, .xiaomiMiMo:
                    try await validateStandardTextToSpeechConnection(
                        for: provider,
                        apiKey: trimmedAPIKey
                    )
                case .elevenlabs:
                    try await validateElevenLabsTextToSpeechConnection(apiKey: trimmedAPIKey)
                }

                await MainActor.run {
                    isTesting = false
                    statusMessage = JinSettingsStatusText.connectionVerifiedMessage
                    statusIsError = false
                }

                switch provider {
                case .openai, .openRouter, .groq, .mistral, .xiaomiMiMo:
                    await loadRemoteTextToSpeechModels(updateStatus: false)
                case .elevenlabs:
                    await loadElevenLabsVoicesAndModels(updateStatus: false)
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    // Endpoint scopes are an ElevenLabs concept; pointing other providers at
                    // that remediation sends the user down the wrong path.
                    if provider == .elevenlabs,
                       let llmError = error as? LLMError,
                       case .authenticationFailed = llmError {
                        statusMessage = "\(llmError.localizedDescription)\n\nIf your ElevenLabs key uses endpoint scopes, enable access to /v1/text-to-speech."
                    } else {
                        statusMessage = error.localizedDescription
                    }
                    statusIsError = true
                }
            }
        }
    }

    private func validateStandardTextToSpeechConnection(
        for provider: TextToSpeechProvider,
        apiKey: String
    ) async throws {
        guard let client = standardTextToSpeechRemoteClient(for: provider, apiKey: apiKey) else { return }
        try await client.validateAPIKey()
    }

    private func validateElevenLabsTextToSpeechConnection(apiKey: String) async throws {
        let client = elevenLabsTextToSpeechRemoteClient(apiKey: apiKey)
        let voices = try await client.listVoices()

        let selectedVoice = elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceIdToTest = !selectedVoice.isEmpty ? selectedVoice : (voices.first?.voiceId ?? "")
        guard !voiceIdToTest.isEmpty else {
            throw SpeechExtensionError.missingElevenLabsVoice
        }

        let selectedModel = elevenLabsModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .elevenlabs,
            modelID: selectedModel
        )

        let voiceSettings = ElevenLabsTTSClient.VoiceSettings(
            stability: elevenLabsStability,
            similarityBoost: elevenLabsSimilarityBoost,
            style: elevenLabsStyle,
            useSpeakerBoost: elevenLabsUseSpeakerBoost,
            speed: capabilities.supportsSpeed ? elevenLabsSpeed : nil
        )

        // Validate that this key can actually synthesize audio (keys may be scope-restricted per endpoint).
        _ = try await client.createSpeech(
            text: "Hello from Jin.",
            voiceId: voiceIdToTest,
            modelId: selectedModel.isEmpty ? nil : elevenLabsModelID,
            outputFormat: elevenLabsOutputFormat,
            optimizeStreamingLatency: elevenLabsOptimizeStreamingLatency,
            enableLogging: elevenLabsEnableLogging,
            voiceSettings: voiceSettings
        )
    }
}
