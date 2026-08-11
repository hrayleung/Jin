import Foundation

extension TextToSpeechPlaybackManager {
    enum State: Equatable {
        case idle
        case generating(messageID: UUID)
        case playing(messageID: UUID)
        case paused(messageID: UUID)

        var activeMessageID: UUID? {
            switch self {
            case .generating(let id), .playing(let id), .paused(let id):
                return id
            case .idle:
                return nil
            }
        }
    }

    struct OpenAIConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String
        let responseFormat: String
        let speed: Double?
        let instructions: String?
        let streamingEnabled: Bool
    }

    /// OpenRouter's speech schema has no `instructions`, and documents `speed` as honoured
    /// only by OpenAI TTS models — which it no longer serves.
    struct OpenRouterConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String
        let responseFormat: String
    }

    struct GroqConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String
        let responseFormat: String
    }

    struct MistralConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voiceId: String
        let responseFormat: String
    }

    struct ElevenLabsConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let voiceId: String
        let modelId: String?
        let outputFormat: String?
        let optimizeStreamingLatency: Int?
        let enableLogging: Bool?
        let voiceSettings: ElevenLabsTTSClient.VoiceSettings?
        let streamingEnabled: Bool
    }

    struct MiMoConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String?
        let responseFormat: String
        let styleInstruction: String?
        let voiceCloneSampleURL: URL?
        let streamingEnabled: Bool
    }

    enum SynthesisConfig: Sendable {
        case openai(OpenAIConfig)
        case openRouter(OpenRouterConfig)
        case groq(GroqConfig)
        case mistral(MistralConfig)
        case elevenlabs(ElevenLabsConfig)
        case mimo(MiMoConfig)
    }

    struct PlaybackContext: Equatable {
        let conversationID: UUID
        let conversationTitle: String
        let textPreview: String
    }
}
