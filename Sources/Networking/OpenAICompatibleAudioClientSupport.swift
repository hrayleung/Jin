import Foundation
import Alamofire

enum OpenAICompatibleAudioClientSupport {
    struct MultipartField {
        let name: String
        let value: String
    }

    struct AvailableModel: Decodable {
        let id: String
        let name: String?
    }

    private struct TranscriptionJSONResponse: Decodable {
        struct Segment: Decodable {
            let text: String?
        }

        let text: String?
        let segments: [Segment]?
    }

    private struct AvailableModelsResponse: Decodable {
        let data: [AvailableModel]
    }

    /// Builds the multipart fields for a transcription request, emitting only what the
    /// selected model accepts.
    ///
    /// The generations diverge enough that sending the union is a guaranteed 400: `gpt-transcribe`
    /// takes `languages[]`/`keywords[]` and rejects `language`, `temperature` and timestamps,
    /// while `whisper-1` is the only model that still returns subtitles or timestamps.
    static func transcriptionFields(
        model: String,
        capabilities: SpeechTranscriptionCapabilities,
        language: String?,
        languages: [String]? = nil,
        keywords: [String]? = nil,
        prompt: String?,
        responseFormat: String?,
        temperature: Double?,
        timestampGranularities: [String]?,
        diarize: Bool? = nil
    ) -> [MultipartField] {
        var fields: [MultipartField] = [MultipartField(name: "model", value: model)]

        let resolvedGranularities = resolvedTimestampGranularities(
            timestampGranularities,
            capabilities: capabilities
        )
        // Mistral rejects a language hint and timestamps in the same request.
        let suppressesLanguage = capabilities.timestampsConflictWithLanguage
            && !resolvedGranularities.isEmpty

        if !suppressesLanguage {
            switch capabilities.languageParameter {
            case .none:
                break
            case .single:
                if let value = singleLanguage(language: language, languages: languages) {
                    fields.append(MultipartField(name: "language", value: value))
                }
            case .multiple:
                fields.append(
                    contentsOf: repeatedFields(
                        name: "languages[]",
                        values: multipleLanguages(language: language, languages: languages)
                    )
                )
            }
        }

        if capabilities.supportsPrompt, let field = optionalField(name: "prompt", value: prompt) {
            fields.append(field)
        }

        if capabilities.supportsKeywords {
            fields.append(contentsOf: repeatedFields(name: "keywords[]", values: normalizedList(keywords)))
        }

        if let format = resolvedResponseFormat(responseFormat, capabilities: capabilities) {
            fields.append(MultipartField(name: "response_format", value: format))
        }

        if capabilities.supportsTemperature, let field = optionalField(name: "temperature", value: temperature) {
            fields.append(field)
        }

        if capabilities.supportsDiarization, let diarize {
            fields.append(MultipartField(name: "diarize", value: String(diarize)))
        }

        fields.append(
            contentsOf: repeatedFields(name: "timestamp_granularities[]", values: resolvedGranularities)
        )

        return fields
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

    /// Clamps a stored `response_format` preference to something the model accepts. Callers
    /// must decode the response against this value, not the raw preference.
    static func resolvedResponseFormat(
        _ responseFormat: String?,
        capabilities: SpeechTranscriptionCapabilities
    ) -> String? {
        SpeechModelCapabilityRegistry.resolvedResponseFormat(
            responseFormat,
            supported: capabilities.responseFormats,
            fallback: capabilities.responseFormats.first ?? "json"
        )
    }

    static func append(_ fields: [MultipartField], to formData: MultipartFormData) {
        for field in fields {
            formData.append(Data(field.value.utf8), withName: field.name)
        }
    }

    static func decodeTranscriptionResponse(_ data: Data, responseFormat: String?) throws -> String {
        let format = normalizedResponseFormat(responseFormat)
        if !jsonResponseFormats.contains(format) {
            return String(data: data, encoding: .utf8) ?? ""
        }

        do {
            let decoded = try JSONDecoder().decode(TranscriptionJSONResponse.self, from: data)
            if let text = decoded.text {
                return text
            }
            // `diarized_json` carries the transcript on the segments rather than the root.
            guard let segments = decoded.segments else { return "" }
            return segments.compactMap { $0.text?.trimmedNonEmpty }.joined(separator: " ")
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    static func decodeAvailableModels(_ data: Data) throws -> [SpeechProviderModelChoice] {
        do {
            let decoded = try JSONDecoder().decode(AvailableModelsResponse.self, from: data)
            return decoded.data.map { model in
                SpeechProviderModelChoice(
                    id: model.id,
                    name: normalizedTrimmedString(model.name)
                )
            }
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    private static let jsonResponseFormats: Set<String> = ["json", "verbose_json", "diarized_json"]

    private static func singleLanguage(language: String?, languages: [String]?) -> String? {
        if let value = language?.trimmedNonEmpty { return value }
        return normalizedList(languages).first
    }

    private static func multipleLanguages(language: String?, languages: [String]?) -> [String] {
        let explicit = normalizedList(languages)
        guard explicit.isEmpty else { return explicit }

        // A stored single-language preference may hold a comma-separated list.
        guard let value = language?.trimmedNonEmpty else { return [] }
        return normalizedList(value.components(separatedBy: ","))
    }

    private static func resolvedTimestampGranularities(
        _ granularities: [String]?,
        capabilities: SpeechTranscriptionCapabilities
    ) -> [String] {
        guard !capabilities.timestampGranularities.isEmpty else { return [] }
        return normalizedList(granularities).filter { capabilities.timestampGranularities.contains($0) }
    }

    private static func normalizedList(_ values: [String]?) -> [String] {
        guard let values else { return [] }
        return values.compactMap { $0.trimmedNonEmpty }
    }

    private static func optionalField(name: String, value: String?) -> MultipartField? {
        guard let value, value.trimmedNonEmpty != nil else {
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
        (responseFormat ?? "json").trimmedLowercased
    }
}
