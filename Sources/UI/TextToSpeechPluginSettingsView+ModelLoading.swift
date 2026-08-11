import Foundation

// MARK: - Model & Voice Loading

extension TextToSpeechPluginSettingsView {

    func loadRemoteTextToSpeechModels(updateStatus: Bool = true) async {
        guard let load = await MainActor.run(body: { textToSpeechLoadSnapshot() }) else { return }
        guard !load.apiKey.isEmpty else { return }
        guard load.provider != .elevenlabs else { return }

        await MainActor.run {
            guard isCurrentTextToSpeechLoad(
                provider: load.provider,
                providerRaw: load.providerRaw,
                apiKey: load.apiKey
            ) else { return }
            isLoadingModels = true
        }

        do {
            let resources = try await fetchRemoteTextToSpeechResources(
                for: load.provider,
                apiKey: load.apiKey
            )

            let filteredModels = SpeechProviderModelCatalog.textToSpeechChoices(
                for: load.provider,
                availableModels: resources.models
            )

            await MainActor.run {
                guard isCurrentTextToSpeechLoad(
                    provider: load.provider,
                    providerRaw: load.providerRaw,
                    apiKey: load.apiKey
                ) else { return }
                // Voice catalogs are written here rather than at fetch time so a response
                // that lands after the user switched provider or key cannot overwrite them.
                applyFetchedVoiceCatalogs(resources)
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

    /// Models plus whatever voice catalog came back in the same round trip. Both are applied
    /// together under the caller's load-snapshot guard.
    private struct FetchedTextToSpeechResources: Sendable {
        var models: [SpeechProviderModelChoice] = []
        var openRouterVoices: [String: [String]]?
        var mistralVoices: [MistralTTSClient.Voice]?
    }

    private func fetchRemoteTextToSpeechResources(
        for provider: TextToSpeechProvider,
        apiKey: String
    ) async throws -> FetchedTextToSpeechResources {
        // OpenRouter reports each model's voice catalog inline, so take the richer shape and
        // carry the voices back with the models.
        if provider == .openRouter {
            let base = URL(string: openRouterBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? OpenRouterAudioClient.Constants.defaultBaseURL
            let client = OpenRouterAudioClient(apiKey: apiKey, baseURL: base)
            let models = try await client.listSpeechModelsWithVoices()
            return FetchedTextToSpeechResources(
                models: models.map(\.choice),
                openRouterVoices: Dictionary(
                    models.map { ($0.id, $0.supportedVoices) },
                    uniquingKeysWith: { first, _ in first }
                )
            )
        }

        if provider == .mistral {
            let client = mistralTextToSpeechRemoteClient(apiKey: apiKey)
            async let models = client.listModels()
            async let voices = client.listVoices()
            return FetchedTextToSpeechResources(
                models: try await models,
                mistralVoices: try await voices
                    .sorted { ($0.name ?? $0.id).localizedStandardCompare($1.name ?? $1.id) == .orderedAscending }
            )
        }

        guard let client = standardTextToSpeechRemoteClient(for: provider, apiKey: apiKey) else {
            return FetchedTextToSpeechResources()
        }
        return FetchedTextToSpeechResources(models: try await client.listModels())
    }

    @MainActor
    private func applyFetchedVoiceCatalogs(_ resources: FetchedTextToSpeechResources) {
        if let openRouterVoices = resources.openRouterVoices {
            openRouterModelVoices = openRouterVoices
            normalizeOpenRouterVoiceIfNeeded()
        }

        if let voices = resources.mistralVoices {
            mistralVoices = voices
            if mistralVoiceID.trimmedNonEmpty == nil || !voices.contains(where: { $0.id == mistralVoiceID }) {
                mistralVoiceID = voices.first?.id ?? ""
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

        let client = elevenLabsTextToSpeechRemoteClient(apiKey: load.apiKey)

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
        case .openRouter:
            openRouterModels = []
            openRouterModelVoices = [:]
        case .groq:
            groqModels = []
        case .mistral:
            mistralModels = []
            mistralVoices = []
        case .xiaomiMiMo:
            miMoModels = []
        case .elevenlabs:
            elevenLabsVoices = []
            elevenLabsModels = []
            isPlayingVoicePreview = false
            voicePreviewPlayer?.stop()
            voicePreviewPlayer = nil
        case .none:
            openAIModels = []
            openRouterModels = []
            openRouterModelVoices = [:]
            groqModels = []
            mistralModels = []
            mistralVoices = []
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
        case .openRouter:
            openRouterModels = models
        case .groq:
            groqModels = models
        case .mistral:
            mistralModels = models
        case .xiaomiMiMo:
            miMoModels = models
        case .elevenlabs:
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
        case .openRouter:
            let currentModel = openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty {
                openRouterModel = models.first?.id ?? openRouterModel
            } else {
                let normalizedModel = SpeechProviderModelCatalog.normalizedOpenRouterTextToSpeechModelID(currentModel)
                if normalizedModel != currentModel {
                    openRouterModel = normalizedModel
                }
            }
            normalizeOpenRouterVoiceIfNeeded()
        case .mistral:
            let currentModel = mistralModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentModel.isEmpty {
                mistralModel = models.first?.id ?? mistralModel
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
        case .elevenlabs:
            break
        }
    }
}
