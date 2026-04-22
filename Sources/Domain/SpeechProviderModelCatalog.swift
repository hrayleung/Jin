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
