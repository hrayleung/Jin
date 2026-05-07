import Foundation

enum TextToSpeechSettingsRemoteClient {
    case openAI(OpenAIAudioClient)
    case groq(GroqAudioClient)
    case miMo(MiMoAudioClient)

    func validateAPIKey(timeoutSeconds: TimeInterval = 30) async throws {
        switch self {
        case .openAI(let client):
            try await client.validateAPIKey(timeoutSeconds: timeoutSeconds)
        case .groq(let client):
            try await client.validateAPIKey(timeoutSeconds: timeoutSeconds)
        case .miMo(let client):
            try await client.validateAPIKey(timeoutSeconds: timeoutSeconds)
        }
    }

    func listModels(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechProviderModelChoice] {
        switch self {
        case .openAI(let client):
            return try await client.listModels(timeoutSeconds: timeoutSeconds)
        case .groq(let client):
            return try await client.listModels(timeoutSeconds: timeoutSeconds)
        case .miMo(let client):
            return try await client.listModels(timeoutSeconds: timeoutSeconds)
        }
    }
}
