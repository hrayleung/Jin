import Foundation

enum TextToSpeechProvider: String, CaseIterable, Identifiable {
    case elevenlabs
    case openai
    case groq
    case xiaomiMiMo
    case whisperKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenlabs: return "ElevenLabs"
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .xiaomiMiMo: return "Xiaomi MiMo"
        case .whisperKit: return "TTSKit (On-Device)"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .elevenlabs, .openai, .groq, .xiaomiMiMo: return true
        case .whisperKit: return false
        }
    }
}

enum SpeechToTextProvider: String, CaseIterable, Identifiable {
    case groq
    case openai
    case mistral
    case elevenlabs
    case whisperKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openai: return "OpenAI"
        case .mistral: return "Mistral"
        case .elevenlabs: return "ElevenLabs"
        case .whisperKit: return "WhisperKit (On-Device)"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .groq, .openai, .mistral, .elevenlabs: return true
        case .whisperKit: return false
        }
    }
}
