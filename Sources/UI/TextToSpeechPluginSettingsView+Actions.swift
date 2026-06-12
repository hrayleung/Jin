// MARK: - Resource Loading Entry Points

extension TextToSpeechPluginSettingsView {

    func loadExistingKeyAndMaybeProviderResources() async {
        let requestedProviderRaw = await MainActor.run { providerRaw }
        await loadExistingKey()

        guard let load = await MainActor.run(body: {
            textToSpeechLoadSnapshot(matchingProviderRaw: requestedProviderRaw)
        }) else { return }

        // Do not automatically call remote model/voice APIs here. Stored base URLs can be
        // user-controlled, so credentials should leave the device only after an explicit
        // Test Connection or speech operation.
        await MainActor.run {
            guard isCurrentTextToSpeechLoad(
                provider: load.provider,
                providerRaw: load.providerRaw,
                apiKey: load.apiKey
            ) else { return }
            clearFetchedTextToSpeechModels(for: load.provider)
        }
    }
}
