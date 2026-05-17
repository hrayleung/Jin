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
    }

    struct OpenRouterConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String
        let responseFormat: String
        let speed: Double?
        let instructions: String?
    }

    struct GroqConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String
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
    }

    struct MiMoConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String?
        let responseFormat: String
        let styleInstruction: String?
        let voiceCloneSampleURL: URL?
    }

    enum SynthesisConfig: Sendable {
        case openai(OpenAIConfig)
        case openRouter(OpenRouterConfig)
        case groq(GroqConfig)
        case elevenlabs(ElevenLabsConfig)
        case mimo(MiMoConfig)
    }

    struct PlaybackContext: Equatable {
        let conversationID: UUID
        let conversationTitle: String
        let textPreview: String
    }
}
