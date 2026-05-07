import Foundation

enum SpeechToTextSettingsRemoteClient {
    case openAI(OpenAIAudioClient)
    case groq(GroqAudioClient)
    case mistral(OpenAIAudioClient)
    case elevenLabs(ElevenLabsSTTClient)

    func validateAPIKey(timeoutSeconds: TimeInterval = 30) async throws {
        switch self {
        case .openAI(let client), .mistral(let client):
            try await client.validateAPIKey(timeoutSeconds: timeoutSeconds)
        case .groq(let client):
            try await client.validateAPIKey(timeoutSeconds: timeoutSeconds)
        case .elevenLabs(let client):
            try await client.validateAPIKey(timeoutSeconds: timeoutSeconds)
        }
    }

    func listModels(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechProviderModelChoice] {
        switch self {
        case .openAI(let client), .mistral(let client):
            return try await client.listModels(timeoutSeconds: timeoutSeconds)
        case .groq(let client):
            return try await client.listModels(timeoutSeconds: timeoutSeconds)
        case .elevenLabs(let client):
            return try await client.listModels(timeoutSeconds: timeoutSeconds)
        }
    }
}
