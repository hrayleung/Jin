import Foundation

struct SpeechProviderModelChoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    init(id: String, name: String? = nil) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.id = trimmedID
        self.name = trimmedName.isEmpty ? trimmedID : trimmedName
    }
}

enum SpeechProviderModelCatalog {
    private static let groqTextToSpeechModelIDs: Set<String> = [
        "canopylabs/orpheus-v1-english",
        "canopylabs/orpheus-arabic-saudi"
    ]

    private static let groqSpeechToTextModelIDs: Set<String> = [
        "whisper-large-v3",
        "whisper-large-v3-turbo"
    ]

    static func textToSpeechChoices(
        for provider: TextToSpeechProvider,
        availableModels: [SpeechProviderModelChoice]
    ) -> [SpeechProviderModelChoice] {
        switch provider {
        case .openai:
            return filteredChoices(availableModels, matches: matchesOpenAITextToSpeechModelID)
        case .groq:
            return filteredChoices(availableModels, matches: matchesGroqTextToSpeechModelID)
        case .elevenlabs, .whisperKit:
            return []
        }
    }

    static func speechToTextChoices(
        for provider: SpeechToTextProvider,
        availableModels: [SpeechProviderModelChoice]
    ) -> [SpeechProviderModelChoice] {
        switch provider {
        case .openai:
            return filteredChoices(availableModels, matches: matchesOpenAISpeechToTextModelID)
        case .groq:
            return filteredChoices(availableModels, matches: matchesGroqSpeechToTextModelID)
        case .mistral:
            return filteredChoices(availableModels, matches: matchesMistralSpeechToTextModelID)
        case .elevenlabs:
            return filteredChoices(availableModels, matches: matchesElevenLabsSpeechToTextModelID)
        case .whisperKit:
            return []
        }
    }

    static func presentingChoices(
        _ choices: [SpeechProviderModelChoice],
        selectedModelID: String
    ) -> [SpeechProviderModelChoice] {
        let trimmedSelection = selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { return choices }
        guard !choices.contains(where: { $0.id == trimmedSelection }) else { return choices }
        return [SpeechProviderModelChoice(id: trimmedSelection)] + choices
    }

    static func defaultTextToSpeechChoices(
        for provider: TextToSpeechProvider
    ) -> [SpeechProviderModelChoice] {
        switch provider {
        case .openai:
            return [
                SpeechProviderModelChoice(id: "gpt-4o-mini-tts", name: "GPT-4o mini TTS"),
                SpeechProviderModelChoice(id: "tts-1", name: "TTS-1"),
                SpeechProviderModelChoice(id: "tts-1-hd", name: "TTS-1 HD")
            ]
        case .groq:
            return [
                SpeechProviderModelChoice(id: "canopylabs/orpheus-v1-english", name: "Orpheus English"),
                SpeechProviderModelChoice(id: "canopylabs/orpheus-arabic-saudi", name: "Orpheus Arabic Saudi")
            ]
        case .elevenlabs:
            return [
                SpeechProviderModelChoice(id: "eleven_multilingual_v2", name: "Eleven Multilingual v2"),
                SpeechProviderModelChoice(id: "eleven_flash_v2_5", name: "Eleven Flash v2.5"),
                SpeechProviderModelChoice(id: "eleven_flash_v2", name: "Eleven Flash v2"),
                SpeechProviderModelChoice(id: "eleven_turbo_v2_5", name: "Eleven Turbo v2.5"),
                SpeechProviderModelChoice(id: "eleven_turbo_v2", name: "Eleven Turbo v2"),
                SpeechProviderModelChoice(id: "eleven_v3", name: "Eleven v3")
            ]
        case .whisperKit:
            return []
        }
    }

    static func defaultSpeechToTextChoices(
        for provider: SpeechToTextProvider
    ) -> [SpeechProviderModelChoice] {
        switch provider {
        case .openai:
            return [
                SpeechProviderModelChoice(id: "gpt-4o-mini-transcribe", name: "GPT-4o mini Transcribe"),
                SpeechProviderModelChoice(id: "gpt-4o-transcribe", name: "GPT-4o Transcribe"),
                SpeechProviderModelChoice(id: "gpt-4o-transcribe-diarize", name: "GPT-4o Transcribe Diarize"),
                SpeechProviderModelChoice(id: "whisper-1", name: "Whisper-1")
            ]
        case .groq:
            return [
                SpeechProviderModelChoice(id: "whisper-large-v3-turbo", name: "Whisper Large v3 Turbo"),
                SpeechProviderModelChoice(id: "whisper-large-v3", name: "Whisper Large v3")
            ]
        case .mistral:
            return [
                SpeechProviderModelChoice(id: "voxtral-mini-latest", name: "Voxtral Mini Latest")
            ]
        case .elevenlabs:
            return [
                SpeechProviderModelChoice(id: "scribe_v2", name: "Scribe v2"),
                SpeechProviderModelChoice(id: "scribe_v1", name: "Scribe v1")
            ]
        case .whisperKit:
            return []
        }
    }

    private static func filteredChoices(
        _ choices: [SpeechProviderModelChoice],
        matches: (String) -> Bool
    ) -> [SpeechProviderModelChoice] {
        var seenIDs = Set<String>()

        return choices
            .filter { choice in
                let modelID = choice.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !modelID.isEmpty else { return false }
                guard matches(modelID.lowercased()) else { return false }
                guard seenIDs.insert(modelID).inserted else { return false }
                return true
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func matchesOpenAITextToSpeechModelID(_ modelID: String) -> Bool {
        modelID == "tts-1"
            || modelID == "tts-1-hd"
            || modelID == "gpt-4o-mini-tts"
            || modelID.hasPrefix("gpt-4o-mini-tts-")
    }

    private static func matchesOpenAISpeechToTextModelID(_ modelID: String) -> Bool {
        modelID == "whisper-1"
            || modelID == "gpt-4o-transcribe"
            || modelID.hasPrefix("gpt-4o-transcribe-")
            || modelID == "gpt-4o-mini-transcribe"
            || modelID.hasPrefix("gpt-4o-mini-transcribe-")
    }

    private static func matchesGroqTextToSpeechModelID(_ modelID: String) -> Bool {
        groqTextToSpeechModelIDs.contains(modelID)
    }

    private static func matchesGroqSpeechToTextModelID(_ modelID: String) -> Bool {
        groqSpeechToTextModelIDs.contains(modelID)
    }

    private static func matchesMistralSpeechToTextModelID(_ modelID: String) -> Bool {
        guard !modelID.contains("realtime") else { return false }

        return modelID == "voxtral-mini-latest"
            || (modelID.contains("voxtral") && modelID.contains("transcribe"))
    }

    private static func matchesElevenLabsSpeechToTextModelID(_ modelID: String) -> Bool {
        modelID.hasPrefix("scribe_") && !modelID.contains("realtime")
    }
}
