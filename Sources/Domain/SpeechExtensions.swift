import Foundation

enum TextToSpeechProvider: String, CaseIterable, Identifiable {
    case elevenlabs
    case openai
    case openRouter
    case groq
    case xiaomiMiMo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenlabs: return "ElevenLabs"
        case .openai: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .xiaomiMiMo: return "Xiaomi MiMo"
        }
    }

    var requiresAPIKey: Bool { true }
}

enum SpeechToTextProvider: String, CaseIterable, Identifiable {
    case groq
    case openai
    case openRouter
    case mistral
    case elevenlabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openai: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .mistral: return "Mistral"
        case .elevenlabs: return "ElevenLabs"
        }
    }

    var requiresAPIKey: Bool { true }
}
