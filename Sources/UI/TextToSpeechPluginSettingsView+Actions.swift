// MARK: - Resource Loading Entry Points

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
        case .openai, .openRouter, .groq, .xiaomiMiMo:
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
}
