import Foundation
import Alamofire

/// Mistral Voxtral text-to-speech.
///
/// Shaped like the OpenAI speech endpoint but with two deliberate differences: the voice is
/// passed as `voice_id`, and the response is JSON carrying base64 audio in `audio_data`
/// rather than raw bytes.
actor MistralTTSClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://api.mistral.ai/v1")!
        static let defaultModel = SpeechProviderModelCatalog.defaultMistralTextToSpeechModelID
        static let defaultResponseFormat = "mp3"
        /// The voices endpoint paginates; Mistral ships 20 presets today.
        static let voicePageSize = 200
    }

    struct Voice: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String?
        /// `nil` for Mistral's built-in presets; set for cloned voices.
        let userId: String?
    }

    private struct VoicesResponse: Decodable {
        let items: [Voice]
    }

    private struct SpeechRequest: Encodable {
        let model: String
        let input: String
        let voiceId: String?
        let responseFormat: String?

        enum CodingKeys: String, CodingKey {
            case model
            case input
            case voiceId = "voice_id"
            case responseFormat = "response_format"
        }
    }

    private struct SpeechResponse: Decodable {
        let audioData: String?

        enum CodingKeys: String, CodingKey {
            case audioData = "audio_data"
        }
    }

    private let apiKey: String
    private let baseURL: URL
    private let networkManager: NetworkManager

    init(
        apiKey: String,
        baseURL: URL = Constants.defaultBaseURL,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.networkManager = networkManager
    }

    func validateAPIKey(timeoutSeconds: TimeInterval = 30) async throws {
        let request = NetworkRequestFactory.makeRequest(
            url: baseURL.appendingPathComponent("models"),
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey)
        )

        _ = try await networkManager.sendRequest(request)
    }

    func listModels(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechProviderModelChoice] {
        let request = NetworkRequestFactory.makeRequest(
            url: baseURL.appendingPathComponent("models"),
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey)
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let models = try OpenAICompatibleAudioClientSupport.decodeAvailableModels(data)
        return SpeechProviderModelCatalog.textToSpeechChoices(
            for: .mistral,
            availableModels: models
        )
    }

    /// Mistral does not publish a static preset table, so the picker has to be populated
    /// from this endpoint.
    func listVoices(timeoutSeconds: TimeInterval = 30) async throws -> [Voice] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("audio/voices"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "type", value: "preset"),
            URLQueryItem(name: "limit", value: String(Constants.voicePageSize))
        ]

        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Invalid Mistral voices URL.")
        }

        let request = NetworkRequestFactory.makeRequest(
            url: url,
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey)
        )

        let (data, _) = try await networkManager.sendRequest(request)
        do {
            let decoded = try JSONDecoder.snakeCaseConverting().decode(VoicesResponse.self, from: data)
            return decoded.items
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    func createSpeech(
        input: String,
        model: String,
        voiceId: String? = nil,
        responseFormat: String? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> Data {
        let body = SpeechRequest(
            model: normalizedTrimmedString(model) ?? Constants.defaultModel,
            input: input,
            voiceId: normalizedTrimmedString(voiceId),
            responseFormat: normalizedTrimmedString(responseFormat) ?? Constants.defaultResponseFormat
        )

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: baseURL.appendingPathComponent("audio/speech"),
            timeoutSeconds: timeoutSeconds,
            headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey),
            body: body
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return try decodeAudioData(from: data)
    }

    private func decodeAudioData(from data: Data) throws -> Data {
        do {
            let decoded = try JSONDecoder().decode(SpeechResponse.self, from: data)
            guard let encodedAudio = decoded.audioData?.trimmedNonEmpty,
                  let audioData = Data(base64Encoded: encodedAudio) else {
                throw LLMError.decodingError(message: "Mistral response did not contain audio data.")
            }
            return audioData
        } catch let error as LLMError {
            throw error
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }
}
