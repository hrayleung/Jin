import Foundation
import Alamofire

enum OpenAICompatibleAudioClientSupport {
    struct MultipartField {
        let name: String
        let value: String
    }

    private struct TranscriptionJSONResponse: Decodable {
        let text: String?
    }

    static func transcriptionFields(
        model: String,
        language: String?,
        prompt: String?,
        responseFormat: String?,
        temperature: Double?,
        timestampGranularities: [String]?
    ) -> [MultipartField] {
        [
            MultipartField(name: "model", value: model),
            optionalField(name: "language", value: language),
            optionalField(name: "prompt", value: prompt),
            optionalField(name: "response_format", value: responseFormat),
            optionalField(name: "temperature", value: temperature)
        ].compactMap { $0 } + repeatedFields(name: "timestamp_granularities[]", values: timestampGranularities)
    }

    static func translationFields(
        model: String,
        prompt: String?,
        responseFormat: String?,
        temperature: Double?
    ) -> [MultipartField] {
        [
            MultipartField(name: "model", value: model),
            optionalField(name: "prompt", value: prompt),
            optionalField(name: "response_format", value: responseFormat),
            optionalField(name: "temperature", value: temperature)
        ].compactMap { $0 }
    }

    static func append(_ fields: [MultipartField], to formData: MultipartFormData) {
        for field in fields {
            formData.append(Data(field.value.utf8), withName: field.name)
        }
    }

    static func decodeTranscriptionResponse(_ data: Data, responseFormat: String?) throws -> String {
        let format = normalizedResponseFormat(responseFormat)
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

    private static func optionalField(name: String, value: String?) -> MultipartField? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return MultipartField(name: name, value: value)
    }

    private static func optionalField(name: String, value: Double?) -> MultipartField? {
        guard let value else { return nil }
        return MultipartField(name: name, value: String(value))
    }

    private static func repeatedFields(name: String, values: [String]?) -> [MultipartField] {
        guard let values, !values.isEmpty else { return [] }
        return values.map { MultipartField(name: name, value: $0) }
    }

    private static func normalizedResponseFormat(_ responseFormat: String?) -> String {
        (responseFormat ?? "json").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
