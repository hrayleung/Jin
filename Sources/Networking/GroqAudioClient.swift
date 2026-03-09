import Foundation
import Alamofire

actor GroqAudioClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://api.groq.com/openai/v1")!
    }

    private struct SpeechRequest: Encodable {
        let model: String
        let input: String
        let voice: String
        let responseFormat: String?

        enum CodingKeys: String, CodingKey {
            case model
            case input
            case voice
            case responseFormat = "response_format"
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

    func createSpeech(
        input: String,
        model: String,
        voice: String,
        responseFormat: String? = "wav",
        timeoutSeconds: TimeInterval = 120
    ) async throws -> Data {
        let body = SpeechRequest(
            model: model,
            input: input,
            voice: voice,
            responseFormat: responseFormat
        )

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: baseURL.appendingPathComponent("audio/speech"),
            timeoutSeconds: timeoutSeconds,
            headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey),
            body: body
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return data
    }

    func createTranscription(
        fileData: Data,
        filename: String,
        mimeType: String,
        model: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: Double? = nil,
        timestampGranularities: [String]? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        let fields = OpenAICompatibleAudioClientSupport.transcriptionFields(
            model: model,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature,
            timestampGranularities: timestampGranularities
        )

        let request = try NetworkRequestFactory.makeMultipartRequest(
            url: baseURL.appendingPathComponent("audio/transcriptions"),
            timeoutSeconds: timeoutSeconds,
            headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey)
        ) { formData in
            formData.append(fileData, withName: "file", fileName: filename, mimeType: mimeType)
            OpenAICompatibleAudioClientSupport.append(fields, to: formData)
        }

        let (data, _) = try await networkManager.sendRequest(request)
        return try OpenAICompatibleAudioClientSupport.decodeTranscriptionResponse(
            data,
            responseFormat: responseFormat
        )
    }

    func createTranslation(
        fileData: Data,
        filename: String,
        mimeType: String,
        model: String,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: Double? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        let fields = OpenAICompatibleAudioClientSupport.translationFields(
            model: model,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        let request = try NetworkRequestFactory.makeMultipartRequest(
            url: baseURL.appendingPathComponent("audio/translations"),
            timeoutSeconds: timeoutSeconds,
            headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey)
        ) { formData in
            formData.append(fileData, withName: "file", fileName: filename, mimeType: mimeType)
            OpenAICompatibleAudioClientSupport.append(fields, to: formData)
        }

        let (data, _) = try await networkManager.sendRequest(request)
        return try OpenAICompatibleAudioClientSupport.decodeTranscriptionResponse(
            data,
            responseFormat: responseFormat
        )
    }
}
