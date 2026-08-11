import Foundation
import Alamofire

actor OpenRouterAudioClient {
    enum Constants {
        static let defaultBaseURL = URL(string: OpenRouterProviderSupport.defaultBaseURL)!
    }

    enum ModalityFilter: String {
        case textToSpeech = "speech"
        case transcription = "transcription"
    }

    /// A speech model plus the voices OpenRouter reports for it. `supportedVoices` is null for
    /// models that accept arbitrary provider voice IDs (MiniMax, Fish Audio).
    struct SpeechModel: Sendable, Hashable {
        let id: String
        let name: String?
        let supportedVoices: [String]

        var choice: SpeechProviderModelChoice {
            SpeechProviderModelChoice(id: id, name: name)
        }
    }

    private struct SpeechModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
            let name: String?
            let supportedVoices: [String]?

            enum CodingKeys: String, CodingKey {
                case id
                case name
                case supportedVoices = "supported_voices"
            }
        }

        let data: [Model]
    }

    private struct SpeechRequest: Encodable {
        let model: String
        let input: String
        let voice: String?
        let responseFormat: String?
        let speed: Double?

        enum CodingKeys: String, CodingKey {
            case model
            case input
            case voice
            case responseFormat = "response_format"
            case speed
        }
    }

    private struct TranscriptionInputAudio: Encodable {
        let data: String
        let format: String
    }

    private struct TranscriptionRequest: Encodable {
        let model: String
        let inputAudio: TranscriptionInputAudio
        let language: String?
        let temperature: Double?
        let responseFormat: String?
        let timestampGranularities: [String]?

        enum CodingKeys: String, CodingKey {
            case model
            case inputAudio = "input_audio"
            case language
            case temperature
            case responseFormat = "response_format"
            case timestampGranularities = "timestamp_granularities"
        }
    }

    private struct TranscriptionResponse: Decodable {
        let text: String?
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
            headers: authorizedHeaders()
        )

        _ = try await networkManager.sendRequest(request)
    }

    func listSpeechModels(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechProviderModelChoice] {
        try await listSpeechModelsWithVoices(timeoutSeconds: timeoutSeconds).map(\.choice)
    }

    /// OpenRouter reports each speech model's voice catalog inline, which is the only way to
    /// populate a voice picker for the non-OpenAI models it now serves.
    func listSpeechModelsWithVoices(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechModel] {
        let data = try await modelsResponse(filter: .textToSpeech, timeoutSeconds: timeoutSeconds)
        do {
            let decoded = try JSONDecoder().decode(SpeechModelsResponse.self, from: data)
            return decoded.data.map { model in
                SpeechModel(
                    id: model.id,
                    name: model.name,
                    supportedVoices: (model.supportedVoices ?? []).compactMap { $0.trimmedNonEmpty }
                )
            }
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    func listTranscriptionModels(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechProviderModelChoice] {
        let data = try await modelsResponse(filter: .transcription, timeoutSeconds: timeoutSeconds)
        return try OpenAICompatibleAudioClientSupport.decodeAvailableModels(data)
    }

    func createSpeech(
        input: String,
        model: String,
        voice: String,
        responseFormat: String? = nil,
        speed: Double? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> Data {
        let body = SpeechRequest(
            model: model,
            input: input,
            // The schema requires a non-empty voice when present; models with an open voice
            // catalog are happy to fall back to their own default.
            voice: voice.trimmedNonEmpty,
            responseFormat: responseFormat,
            speed: speed
        )

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: baseURL.appendingPathComponent("audio/speech"),
            timeoutSeconds: timeoutSeconds,
            headers: authorizedHeaders(),
            body: body
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return data
    }

    func createTranscription(
        audioData: Data,
        audioFormat: String,
        model: String,
        language: String? = nil,
        temperature: Double? = nil,
        responseFormat: String? = nil,
        timestampGranularities: [String]? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        let granularities = (timestampGranularities ?? []).compactMap { $0.trimmedNonEmpty }
        let body = TranscriptionRequest(
            model: model,
            inputAudio: TranscriptionInputAudio(
                data: audioData.base64EncodedString(),
                format: audioFormat
            ),
            language: language?.trimmedNonEmpty,
            temperature: temperature,
            responseFormat: responseFormat?.trimmedNonEmpty,
            timestampGranularities: granularities.isEmpty ? nil : granularities
        )

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: baseURL.appendingPathComponent("audio/transcriptions"),
            timeoutSeconds: timeoutSeconds,
            headers: authorizedHeaders(),
            body: body
        )

        let (data, _) = try await networkManager.sendRequest(request)

        do {
            let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return decoded.text ?? ""
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    private func modelsResponse(
        filter: ModalityFilter,
        timeoutSeconds: TimeInterval
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("models"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "output_modalities", value: filter.rawValue)]
        guard let url = components?.url else {
            throw LLMError.invalidRequest(message: "Invalid OpenRouter models URL.")
        }

        let request = NetworkRequestFactory.makeRequest(
            url: url,
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: authorizedHeaders()
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return data
    }

    /// Intentionally distinct from `OpenRouterProviderSupport.authorizedHeaders(apiKey:)`:
    /// this returns Alamofire `HTTPHeaders` (the multipart audio upload path needs them)
    /// and deliberately omits the `Accept: application/json` header that the shared
    /// `[String: String]` builder adds. Do not "consolidate" the two without confirming
    /// the audio endpoint tolerates the extra Accept header — it would change the wire request.
    private func authorizedHeaders() -> HTTPHeaders {
        var headers = HTTPHeaders()
        for (name, value) in OpenRouterProviderSupport.appIdentityHeaders {
            headers.update(name: name, value: value)
        }
        headers.update(name: "Authorization", value: "Bearer \(apiKey)")
        return headers
    }
}
