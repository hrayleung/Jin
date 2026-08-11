import Foundation
import Alamofire

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

    struct ModelLanguage: Decodable, Hashable {
        let languageId: String
        let name: String
    }

    struct Model: Decodable, Identifiable, Hashable {
        let modelId: String
        let name: String
        let canDoTextToSpeech: Bool
        let canUseStyle: Bool
        let canUseSpeakerBoost: Bool
        let description: String?
        let languages: [ModelLanguage]?

        var id: String { modelId }
    }

    struct VoiceSettings: Encodable, Hashable {
        let stability: Double?
        let similarityBoost: Double?
        let style: Double?
        let useSpeakerBoost: Bool?
        /// Rejected by the v3 models — gate on `SpeechModelCapabilityRegistry` before sending.
        let speed: Double?

        init(
            stability: Double? = nil,
            similarityBoost: Double? = nil,
            style: Double? = nil,
            useSpeakerBoost: Bool? = nil,
            speed: Double? = nil
        ) {
            self.stability = stability
            self.similarityBoost = similarityBoost
            self.style = style
            self.useSpeakerBoost = useSpeakerBoost
            self.speed = speed
        }

        enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost = "similarity_boost"
            case style
            case useSpeakerBoost = "use_speaker_boost"
            case speed
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
        let applyTextNormalization: String?

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
            case applyTextNormalization = "apply_text_normalization"
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
        let request = NetworkRequestFactory.makeRequest(
            url: baseURL.appendingPathComponent("voices"),
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: [HTTPHeader(name: "xi-api-key", value: apiKey)]
        )

        let (data, _) = try await networkManager.sendRequest(request)
        do {
            let decoded = try JSONDecoder.snakeCaseConverting().decode(VoicesResponse.self, from: data)
            return decoded.voices
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    func listModels(timeoutSeconds: TimeInterval = 30) async throws -> [Model] {
        let request = NetworkRequestFactory.makeRequest(
            url: baseURL.appendingPathComponent("models"),
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: [HTTPHeader(name: "xi-api-key", value: apiKey)]
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return try JSONDecoder.snakeCaseConverting().decodeOrThrowRawBody([Model].self, from: data)
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
        applyTextNormalization: String? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> Data {
        let request = try makeSpeechRequest(
            path: "text-to-speech/\(voiceId)",
            text: text,
            modelId: modelId,
            outputFormat: outputFormat,
            optimizeStreamingLatency: optimizeStreamingLatency,
            enableLogging: enableLogging,
            languageCode: languageCode,
            voiceSettings: voiceSettings,
            pronunciationDictionaryLocators: pronunciationDictionaryLocators,
            seed: seed,
            previousText: previousText,
            nextText: nextText,
            previousRequestIds: previousRequestIds,
            nextRequestIds: nextRequestIds,
            applyTextNormalization: applyTextNormalization,
            timeoutSeconds: timeoutSeconds
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return data
    }

    /// Streams the audio body as it is produced.
    ///
    /// Unlike the OpenAI and MiMo streaming paths this is not SSE — the endpoint returns the
    /// raw encoded audio in chunked transfer encoding.
    func createSpeechStream(
        text: String,
        voiceId: String,
        modelId: String? = nil,
        outputFormat: String? = nil,
        optimizeStreamingLatency: Int? = nil,
        enableLogging: Bool? = nil,
        languageCode: String? = nil,
        voiceSettings: VoiceSettings? = nil,
        applyTextNormalization: String? = nil,
        timeoutSeconds: TimeInterval = 300
    ) async throws -> AsyncThrowingStream<Data, Error> {
        let request = try makeSpeechRequest(
            path: "text-to-speech/\(voiceId)/stream",
            text: text,
            modelId: modelId,
            outputFormat: outputFormat,
            optimizeStreamingLatency: optimizeStreamingLatency,
            enableLogging: enableLogging,
            languageCode: languageCode,
            voiceSettings: voiceSettings,
            pronunciationDictionaryLocators: nil,
            seed: nil,
            previousText: nil,
            nextText: nil,
            previousRequestIds: nil,
            nextRequestIds: nil,
            applyTextNormalization: applyTextNormalization,
            timeoutSeconds: timeoutSeconds
        )

        return await networkManager.streamRequest(request, parser: RawByteChunkParser())
    }

    private func makeSpeechRequest(
        path: String,
        text: String,
        modelId: String?,
        outputFormat: String?,
        optimizeStreamingLatency: Int?,
        enableLogging: Bool?,
        languageCode: String?,
        voiceSettings: VoiceSettings?,
        pronunciationDictionaryLocators: [PronunciationDictionaryLocator]?,
        seed: Int?,
        previousText: String?,
        nextText: String?,
        previousRequestIds: [String]?,
        nextRequestIds: [String]?,
        applyTextNormalization: String?,
        timeoutSeconds: TimeInterval
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []

        if outputFormat?.trimmedNonEmpty != nil {
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
            nextRequestIds: nextRequestIds,
            applyTextNormalization: applyTextNormalization
        )

        return try NetworkRequestFactory.makeJSONRequest(
            url: url,
            timeoutSeconds: timeoutSeconds,
            headers: [HTTPHeader(name: "xi-api-key", value: apiKey)],
            body: body
        )
    }
}
