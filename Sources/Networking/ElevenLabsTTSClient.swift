import Foundation

actor ElevenLabsTTSClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://api.elevenlabs.io/v1")!
    }

    struct Voice: Decodable, Identifiable, Hashable {
        let voiceId: String
        let name: String
        let previewUrl: String?

        var id: String { voiceId }
    }

    private struct VoicesResponse: Decodable {
        let voices: [Voice]
    }

    struct VoiceSettings: Encodable, Hashable {
        let stability: Double?
        let similarityBoost: Double?
        let style: Double?
        let useSpeakerBoost: Bool?

        enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost = "similarity_boost"
            case style
            case useSpeakerBoost = "use_speaker_boost"
        }
    }

    private struct CreateSpeechRequest: Encodable {
        let text: String
        let modelId: String?
        let languageCode: String?
        let voiceSettings: VoiceSettings?
        let pronunciationDictionaryLocators: [PronunciationDictionaryLocator]?
        let seed: Int?
        let previousText: String?
        let nextText: String?
        let previousRequestIds: [String]?
        let nextRequestIds: [String]?

        enum CodingKeys: String, CodingKey {
            case text
            case modelId = "model_id"
            case languageCode = "language_code"
            case voiceSettings = "voice_settings"
            case pronunciationDictionaryLocators = "pronunciation_dictionary_locators"
            case seed
            case previousText = "previous_text"
            case nextText = "next_text"
            case previousRequestIds = "previous_request_ids"
            case nextRequestIds = "next_request_ids"
        }
    }

    struct PronunciationDictionaryLocator: Encodable, Hashable {
        let pronunciationDictionaryId: String
        let versionId: String?

        enum CodingKeys: String, CodingKey {
            case pronunciationDictionaryId = "pronunciation_dictionary_id"
            case versionId = "version_id"
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
        _ = try await listVoices(timeoutSeconds: timeoutSeconds)
    }

    func listVoices(timeoutSeconds: TimeInterval = 30) async throws -> [Voice] {
        var request = URLRequest(url: baseURL.appendingPathComponent("voices"))
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, _) = try await networkManager.sendRequest(request)
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(VoicesResponse.self, from: data)
            return decoded.voices
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    func createSpeech(
        text: String,
        voiceId: String,
        modelId: String? = nil,
        outputFormat: String? = nil,
        optimizeStreamingLatency: Int? = nil,
        enableLogging: Bool? = nil,
        languageCode: String? = nil,
        voiceSettings: VoiceSettings? = nil,
        pronunciationDictionaryLocators: [PronunciationDictionaryLocator]? = nil,
        seed: Int? = nil,
        previousText: String? = nil,
        nextText: String? = nil,
        previousRequestIds: [String]? = nil,
        nextRequestIds: [String]? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("text-to-speech/\(voiceId)"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []

        if let outputFormat, !outputFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "output_format", value: outputFormat))
        }
        if let optimizeStreamingLatency {
            queryItems.append(URLQueryItem(name: "optimize_streaming_latency", value: String(optimizeStreamingLatency)))
        }
        if let enableLogging {
            queryItems.append(URLQueryItem(name: "enable_logging", value: enableLogging ? "true" : "false"))
        }

        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Invalid ElevenLabs URL.")
        }

        let body = CreateSpeechRequest(
            text: text,
            modelId: modelId,
            languageCode: languageCode,
            voiceSettings: voiceSettings,
            pronunciationDictionaryLocators: pronunciationDictionaryLocators,
            seed: seed,
            previousText: previousText,
            nextText: nextText,
            previousRequestIds: previousRequestIds,
            nextRequestIds: nextRequestIds
        )

        let requestBody = try JSONEncoder().encode(body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = requestBody

        let (data, _) = try await networkManager.sendRequest(request)
        return data
    }
}
