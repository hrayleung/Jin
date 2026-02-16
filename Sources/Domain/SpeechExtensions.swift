import Foundation

enum TextToSpeechProvider: String, CaseIterable, Identifiable {
    case elevenlabs
    case openai
    case groq

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenlabs: return "ElevenLabs"
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        }
    }
}

enum SpeechToTextProvider: String, CaseIterable, Identifiable {
    case groq
    case openai
    case mistral

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openai: return "OpenAI"
        case .mistral: return "Mistral"
        }
    }
}
