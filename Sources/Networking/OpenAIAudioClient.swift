import Foundation
import Alamofire

actor OpenAIAudioClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!
    }

    private struct SpeechRequest: Encodable {
        let model: String
        let input: String
        let voice: String
        let responseFormat: String?
        let speed: Double?
        let instructions: String?
        let streamFormat: String?

        enum CodingKeys: String, CodingKey {
            case model
            case input
            case voice
            case responseFormat = "response_format"
            case speed
            case instructions
            case streamFormat = "stream_format"
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
        return try OpenAICompatibleAudioClientSupport.decodeAvailableModels(data)
    }

    func createSpeech(
        input: String,
        model: String,
        voice: String,
        responseFormat: String? = nil,
        speed: Double? = nil,
        instructions: String? = nil,
        streamFormat: String? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> Data {
        let body = SpeechRequest(
            model: model,
            input: input,
            voice: voice,
            responseFormat: responseFormat,
            speed: speed,
            instructions: instructions,
            streamFormat: streamFormat
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

    /// Streams PCM audio as it is synthesised.
    ///
    /// Requires `stream_format: "sse"`, which the tts-1 generation rejects — callers must
    /// consult `SpeechModelCapabilityRegistry` before choosing this path.
    func createSpeechStream(
        input: String,
        model: String,
        voice: String,
        responseFormat: String,
        speed: Double? = nil,
        instructions: String? = nil,
        timeoutSeconds: TimeInterval = 300
    ) async throws -> AsyncThrowingStream<Data, Error> {
        let body = SpeechRequest(
            model: model,
            input: input,
            voice: voice,
            responseFormat: responseFormat,
            speed: speed,
            instructions: instructions,
            streamFormat: "sse"
        )

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: baseURL.appendingPathComponent("audio/speech"),
            timeoutSeconds: timeoutSeconds,
            headers: NetworkRequestFactory.bearerHeaders(apiKey: apiKey),
            body: body
        )

        let events = await networkManager.streamRequest(request, parser: SSEParser())
        return SpeechAudioStreamSupport.openAIAudioChunks(from: events)
    }

    func createTranscription(
        fileData: Data,
        filename: String,
        mimeType: String,
        model: String,
        capabilities: SpeechTranscriptionCapabilities,
        language: String? = nil,
        languages: [String]? = nil,
        keywords: [String]? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: Double? = nil,
        timestampGranularities: [String]? = nil,
        diarize: Bool? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        let fields = OpenAICompatibleAudioClientSupport.transcriptionFields(
            model: model,
            capabilities: capabilities,
            language: language,
            languages: languages,
            keywords: keywords,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature,
            timestampGranularities: timestampGranularities,
            diarize: diarize
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
            responseFormat: OpenAICompatibleAudioClientSupport.resolvedResponseFormat(
                responseFormat,
                capabilities: capabilities
            )
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
