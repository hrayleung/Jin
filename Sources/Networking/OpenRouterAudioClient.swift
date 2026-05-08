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

    private struct SpeechRequest: Encodable {
        let model: String
        let input: String
        let voice: String
        let responseFormat: String?
        let speed: Double?
        let provider: SpeechRequestProvider?

        enum CodingKeys: String, CodingKey {
            case model
            case input
            case voice
            case responseFormat = "response_format"
            case speed
            case provider
        }
    }

    private struct SpeechRequestProvider: Encodable {
        let options: SpeechRequestProviderOptions
    }

    private struct SpeechRequestProviderOptions: Encodable {
        let openAI: SpeechRequestOpenAIOptions

        enum CodingKeys: String, CodingKey {
            case openAI = "openai"
        }
    }

    private struct SpeechRequestOpenAIOptions: Encodable {
        let instructions: String
    }

    private static func speechRequestProvider(forInstructions instructions: String?) -> SpeechRequestProvider? {
        guard let instructions = instructions?.trimmedNonEmpty else { return nil }
        return SpeechRequestProvider(
            options: SpeechRequestProviderOptions(
                openAI: SpeechRequestOpenAIOptions(instructions: instructions)
            )
        )
    }

    private static func shouldForwardInstructions(for model: String) -> Bool {
        model.trimmedLowercased.hasPrefix("openai/")
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

        enum CodingKeys: String, CodingKey {
            case model
            case inputAudio = "input_audio"
            case language
            case temperature
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
        try await listModels(filter: .textToSpeech, timeoutSeconds: timeoutSeconds)
    }

    func listTranscriptionModels(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechProviderModelChoice] {
        try await listModels(filter: .transcription, timeoutSeconds: timeoutSeconds)
    }

    func createSpeech(
        input: String,
        model: String,
        voice: String,
        responseFormat: String? = nil,
        speed: Double? = nil,
        instructions: String? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> Data {
        let body = SpeechRequest(
            model: model,
            input: input,
            voice: voice,
            responseFormat: responseFormat,
            speed: speed,
            provider: Self.shouldForwardInstructions(for: model)
                ? Self.speechRequestProvider(forInstructions: instructions)
                : nil
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
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        let body = TranscriptionRequest(
            model: model,
            inputAudio: TranscriptionInputAudio(
                data: audioData.base64EncodedString(),
                format: audioFormat
            ),
            language: language?.trimmedNonEmpty,
            temperature: temperature
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

    private func listModels(
        filter: ModalityFilter,
        timeoutSeconds: TimeInterval
    ) async throws -> [SpeechProviderModelChoice] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("models"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "output_modalities", value: filter.rawValue)]
        guard let url = components?.url else {
            return []
        }

        let request = NetworkRequestFactory.makeRequest(
            url: url,
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: authorizedHeaders()
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return try OpenAICompatibleAudioClientSupport.decodeAvailableModels(data)
    }

    private func authorizedHeaders() -> HTTPHeaders {
        var headers = HTTPHeaders()
        for (name, value) in OpenRouterProviderSupport.appIdentityHeaders {
            headers.update(name: name, value: value)
        }
        headers.update(name: "Authorization", value: "Bearer \(apiKey)")
        return headers
    }
}
