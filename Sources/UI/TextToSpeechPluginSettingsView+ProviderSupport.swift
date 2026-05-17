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
        case .xiaomiMiMo:
            let base = URL(string: miMoBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? MiMoAudioClient.Constants.defaultBaseURL
            return .miMo(MiMoAudioClient(apiKey: apiKey, baseURL: base))
        case .elevenlabs:
            return nil
        }
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
        let lower = groqModel.trimmedLowercased
        if lower.contains("orpheus-arabic-saudi") {
            return Self.groqOrpheusArabicVoices
        }
        if lower.contains("orpheus-v1-english") || lower.contains("orpheus") {
            return Self.groqOrpheusEnglishVoices
        }
        return (Self.groqOrpheusEnglishVoices + Self.groqOrpheusArabicVoices)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func normalizeGroqVoiceIfNeeded() {
        let choices = groqVoiceChoices
        guard !choices.isEmpty else { return }
        if !choices.contains(groqVoice) {
            groqVoice = choices[0]
        }
    }

    var miMoVoiceChoices: [String] {
        let lower = miMoModel.trimmedLowercased
        if lower == MiMoModelIDs.ttsV2 {
            return Self.miMoV2Voices
        }
        return Self.miMoV25Voices
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

    static let openAIVoices: [String] = [
        "alloy",
        "ash",
        "ballad",
        "cedar",
        "coral",
        "echo",
        "fable",
        "marin",
        "nova",
        "onyx",
        "sage",
        "shimmer",
        "verse"
    ]

    static let openAIResponseFormats: [String] = [
        "mp3",
        "wav",
        "aac",
        "flac",
        "pcm"
    ]

    static let openRouterResponseFormats: [String] = [
        "mp3",
        "pcm"
    ]

    static let groqOrpheusEnglishVoices: [String] = [
        "autumn",
        "diana",
        "hannah",
        "austin",
        "daniel",
        "troy"
    ]

    static let groqOrpheusArabicVoices: [String] = [
        "fahad",
        "sultan",
        "lulwa",
        "noura"
    ]

    static let miMoV25Voices: [String] = [
        "mimo_default",
        "冰糖",
        "茉莉",
        "苏打",
        "白桦",
        "Mia",
        "Chloe",
        "Milo",
        "Dean"
    ]

    static let miMoV2Voices: [String] = [
        "mimo_default",
        "default_en",
        "default_zh"
    ]

    static let elevenLabsOutputFormats: [String] = [
        "mp3_44100_128",
        "mp3_44100_192",
        "pcm_16000",
        "pcm_22050",
        "pcm_24000",
        "pcm_44100"
    ]
}
