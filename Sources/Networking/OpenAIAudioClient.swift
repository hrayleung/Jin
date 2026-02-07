import Foundation

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

    private struct TranscriptionJSONResponse: Decodable {
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
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        _ = try await networkManager.sendRequest(request)
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

        let requestBody = try JSONEncoder().encode(body)

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestBody

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
        var form = MultipartFormDataBuilder()
        form.addFileField(name: "file", filename: filename, mimeType: mimeType, data: fileData)
        form.addField(name: "model", value: model)

        if let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form.addField(name: "language", value: language)
        }
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form.addField(name: "prompt", value: prompt)
        }
        if let responseFormat, !responseFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form.addField(name: "response_format", value: responseFormat)
        }
        if let temperature {
            form.addField(name: "temperature", value: String(temperature))
        }
        if let timestampGranularities, !timestampGranularities.isEmpty {
            for granularity in timestampGranularities {
                form.addField(name: "timestamp_granularities[]", value: granularity)
            }
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue(form.contentTypeHeader(), forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = form.buildBody()

        let (data, _) = try await networkManager.sendRequest(request)

        // If response_format is a text format (e.g., text/srt/vtt), return raw UTF-8.
        let format = (responseFormat ?? "json").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if format != "json" && format != "verbose_json" {
            return String(data: data, encoding: .utf8) ?? ""
        }

        do {
            let decoded = try JSONDecoder().decode(TranscriptionJSONResponse.self, from: data)
            return decoded.text ?? ""
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
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
        var form = MultipartFormDataBuilder()
        form.addFileField(name: "file", filename: filename, mimeType: mimeType, data: fileData)
        form.addField(name: "model", value: model)

        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form.addField(name: "prompt", value: prompt)
        }
        if let responseFormat, !responseFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            form.addField(name: "response_format", value: responseFormat)
        }
        if let temperature {
            form.addField(name: "temperature", value: String(temperature))
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/translations"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue(form.contentTypeHeader(), forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = form.buildBody()

        let (data, _) = try await networkManager.sendRequest(request)

        let format = (responseFormat ?? "json").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if format != "json" && format != "verbose_json" {
            return String(data: data, encoding: .utf8) ?? ""
        }

        do {
            let decoded = try JSONDecoder().decode(TranscriptionJSONResponse.self, from: data)
            return decoded.text ?? ""
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }
}
