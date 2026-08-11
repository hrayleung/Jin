import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension TextToSpeechPluginSettingsView {
    func standardTextToSpeechRemoteClient(
        for provider: TextToSpeechProvider,
        apiKey: String
    ) -> TextToSpeechSettingsRemoteClient? {
        switch provider {
        case .openai:
            let base = URL(string: openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? OpenAIAudioClient.Constants.defaultBaseURL
            return .openAI(OpenAIAudioClient(apiKey: apiKey, baseURL: base))
        case .openRouter:
            let base = URL(string: openRouterBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? OpenRouterAudioClient.Constants.defaultBaseURL
            return .openRouter(OpenRouterAudioClient(apiKey: apiKey, baseURL: base))
        case .groq:
            let base = URL(string: groqBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? GroqAudioClient.Constants.defaultBaseURL
            return .groq(GroqAudioClient(apiKey: apiKey, baseURL: base))
        case .mistral:
            return .mistral(mistralTextToSpeechRemoteClient(apiKey: apiKey))
        case .xiaomiMiMo:
            let base = URL(string: miMoBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? MiMoAudioClient.Constants.defaultBaseURL
            return .miMo(MiMoAudioClient(apiKey: apiKey, baseURL: base))
        case .elevenlabs:
            return nil
        }
    }

    func mistralTextToSpeechRemoteClient(apiKey: String) -> MistralTTSClient {
        let base = URL(string: mistralBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? MistralTTSClient.Constants.defaultBaseURL
        return MistralTTSClient(apiKey: apiKey, baseURL: base)
    }

    /// The model ID currently selected for the active provider.
    var selectedModelID: String {
        switch provider {
        case .openai: return openAIModel
        case .openRouter: return openRouterModel
        case .groq: return groqModel
        case .mistral: return mistralModel
        case .xiaomiMiMo: return miMoModel
        case .elevenlabs: return elevenLabsModelID
        case .none: return ""
        }
    }

    var currentSynthesisCapabilities: SpeechSynthesisCapabilities? {
        guard let provider else { return nil }
        return SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: provider,
            modelID: selectedModelID
        )
    }

    var supportsStreaming: Bool {
        currentSynthesisCapabilities?.streaming != nil
    }

    var streamingSupportingText: String {
        guard supportsStreaming else {
            return "The selected provider or model does not stream audio; Jin waits for the full clip."
        }
        return "Plays audio as it is generated. Overrides the format below with PCM."
    }

    func elevenLabsTextToSpeechRemoteClient(apiKey: String) -> ElevenLabsTTSClient {
        let base = URL(string: elevenLabsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? ElevenLabsTTSClient.Constants.defaultBaseURL
        return ElevenLabsTTSClient(apiKey: apiKey, baseURL: base)
    }

    var selectedElevenLabsVoicePreviewURL: URL? {
        guard provider == .elevenlabs else { return nil }
        guard let voice = elevenLabsVoices.first(where: { $0.voiceId == elevenLabsVoiceID }) else { return nil }
        guard let str = voice.previewUrl, let url = URL(string: str) else { return nil }
        return url
    }

    var availableOpenAIModels: [SpeechProviderModelChoice] {
        openAIModels.isEmpty
            ? SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .openai)
            : openAIModels
    }

    var displayedOpenAIModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableOpenAIModels, selectedModelID: openAIModel)
    }

    var availableOpenRouterModels: [SpeechProviderModelChoice] {
        openRouterModels.isEmpty
            ? SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .openRouter)
            : openRouterModels
    }

    var displayedOpenRouterModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableOpenRouterModels, selectedModelID: openRouterModel)
    }

    var availableGroqModels: [SpeechProviderModelChoice] {
        groqModels.isEmpty
            ? SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .groq)
            : groqModels
    }

    var displayedGroqModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableGroqModels, selectedModelID: groqModel)
    }

    var availableMiMoModels: [SpeechProviderModelChoice] {
        miMoModels.isEmpty
            ? SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .xiaomiMiMo)
            : miMoModels
    }

    var displayedMiMoModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableMiMoModels, selectedModelID: miMoModel)
    }

    var availableMistralModels: [SpeechProviderModelChoice] {
        mistralModels.isEmpty
            ? SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .mistral)
            : mistralModels
    }

    var displayedMistralModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableMistralModels, selectedModelID: mistralModel)
    }

    var availableElevenLabsModels: [SpeechProviderModelChoice] {
        if !elevenLabsModels.isEmpty {
            return elevenLabsModels.map { model in
                SpeechProviderModelChoice(id: model.modelId, name: model.name)
            }
        }
        return SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .elevenlabs)
    }

    var displayedElevenLabsModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(
            availableElevenLabsModels,
            selectedModelID: elevenLabsModelID
        )
    }

    var groqVoiceChoices: [String] {
        SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .groq,
            modelID: groqModel
        ).voices ?? []
    }

    func normalizeGroqVoiceIfNeeded() {
        let choices = groqVoiceChoices
        guard !choices.isEmpty else { return }
        if !choices.contains(groqVoice) {
            groqVoice = choices[0]
        }
    }

    /// OpenRouter reports each model's voices on `/models`; models with an open catalog
    /// report none and fall back to a free-text field.
    var openRouterVoiceChoices: [String] {
        openRouterModelVoices[openRouterModel] ?? []
    }

    func normalizeOpenRouterVoiceIfNeeded() {
        let choices = openRouterVoiceChoices
        guard !choices.isEmpty else { return }
        if !choices.contains(openRouterVoice) {
            openRouterVoice = choices[0]
        }
    }

    var miMoVoiceChoices: [String] {
        SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .xiaomiMiMo,
            modelID: miMoModel
        ).voices ?? []
    }

    func normalizeMiMoVoiceIfNeeded() {
        let choices = miMoVoiceChoices
        guard !choices.isEmpty else { return }
        if !choices.contains(miMoVoice) {
            miMoVoice = choices[0]
        }
    }

    func chooseMiMoVoiceCloneSample() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mp3"),
            UTType(filenameExtension: "wav")
        ].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            miMoVoiceCloneSamplePath = url.path
        }
        #endif
    }

    /// Voice and format catalogs live in `SpeechModelCapabilityRegistry` so the settings UI
    /// and the request builders can never disagree about what a model accepts.
    var openAIVoiceChoices: [String] {
        SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: .openai,
            modelID: openAIModel
        ).voices ?? SpeechModelCapabilityRegistry.openAIVoices
    }

    func normalizeOpenAIVoiceIfNeeded() {
        let choices = openAIVoiceChoices
        guard !choices.isEmpty, !choices.contains(openAIVoice) else { return }
        openAIVoice = choices[0]
    }

    func normalizeMiMoResponseFormatIfNeeded() {
        let formats = MiMoModelIDs.textToSpeechResponseFormats
        guard !formats.contains(miMoResponseFormat) else { return }
        miMoResponseFormat = MiMoAudioClient.Constants.defaultResponseFormat
    }

    static let openAIResponseFormats: [String] = SpeechModelCapabilityRegistry.openAIResponseFormats
    static let openRouterResponseFormats: [String] = SpeechModelCapabilityRegistry.openRouterResponseFormats
    static let mistralResponseFormats: [String] = SpeechModelCapabilityRegistry.mistralResponseFormats
    static let elevenLabsOutputFormats: [String] = SpeechModelCapabilityRegistry.elevenLabsOutputFormats
}
