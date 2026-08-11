import Foundation
import Alamofire

actor ElevenLabsSTTClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://api.elevenlabs.io/v1")!
    }

    private struct AvailableModel: Decodable {
        let modelId: String
        let name: String
    }

    private struct TranscriptionResponse: Decodable {
        let text: String?
        let languageCode: String?
        let languageProbability: Double?
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
        // Validate against the actual transcription endpoint with a minimal
        // silent WAV so scoped keys with speech_to_text but not models_read
        // are tested correctly.
        let silentWAV = Self.minimalSilentWAV()
        let request = try NetworkRequestFactory.makeMultipartRequest(
            url: baseURL.appendingPathComponent("speech-to-text"),
            timeoutSeconds: timeoutSeconds,
            headers: [HTTPHeader(name: "xi-api-key", value: apiKey)]
        ) { formData in
            formData.append(silentWAV, withName: "file", fileName: "test.wav", mimeType: "audio/wav")
            formData.append(Data("scribe_v2".utf8), withName: "model_id")
        }
        _ = try await networkManager.sendRequest(request)
    }

    func listModels(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechProviderModelChoice] {
        let request = NetworkRequestFactory.makeRequest(
            url: baseURL.appendingPathComponent("models"),
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: [HTTPHeader(name: "xi-api-key", value: apiKey)]
        )

        let (data, _) = try await networkManager.sendRequest(request)
        do {
            return try JSONDecoder.snakeCaseConverting().decode([AvailableModel].self, from: data).map { model in
                SpeechProviderModelChoice(id: model.modelId, name: model.name)
            }
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    /// 100ms silent 16-bit PCM WAV at 16kHz (meets ElevenLabs minimum).
    private static func minimalSilentWAV() -> Data {
        let sampleRate = 16_000
        let numSamples = 1_600 // 100ms at 16 kHz
        let pcmData = Data(count: numSamples * 2) // 16-bit samples, all zero
        return TextToSpeechWAVContainer.wrapPCM16LEMono(pcmData: pcmData, sampleRate: sampleRate)
    }

    func createTranscription(
        fileData: Data,
        filename: String,
        mimeType: String,
        modelId: String = "scribe_v2",
        languageCode: String? = nil,
        tagAudioEvents: Bool? = nil,
        numSpeakers: Int? = nil,
        timestampsGranularity: String? = nil,
        diarize: Bool? = nil,
        diarizationThreshold: Double? = nil,
        useMultiChannel: Bool? = nil,
        seed: Int? = nil,
        fileFormat: String? = nil,
        temperature: Double? = nil,
        noVerbatim: Bool? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        let request = try NetworkRequestFactory.makeMultipartRequest(
            url: baseURL.appendingPathComponent("speech-to-text"),
            timeoutSeconds: timeoutSeconds,
            headers: [HTTPHeader(name: "xi-api-key", value: apiKey)]
        ) { formData in
            formData.append(fileData, withName: "file", fileName: filename, mimeType: mimeType)
            formData.append(Data(modelId.utf8), withName: "model_id")

            if let languageCode, !languageCode.isEmpty {
                formData.append(Data(languageCode.utf8), withName: "language_code")
            }
            if let tagAudioEvents {
                formData.append(Data(String(tagAudioEvents).utf8), withName: "tag_audio_events")
            }
            if let numSpeakers {
                formData.append(Data(String(numSpeakers).utf8), withName: "num_speakers")
            }
            // The enum only accepts `word` and `character`; "none" means omit the field.
            if let timestampsGranularity, !timestampsGranularity.isEmpty, timestampsGranularity != "none" {
                formData.append(Data(timestampsGranularity.utf8), withName: "timestamps_granularity")
            }
            if let diarize {
                formData.append(Data(String(diarize).utf8), withName: "diarize")
            }
            if let diarizationThreshold {
                formData.append(Data(String(diarizationThreshold).utf8), withName: "diarization_threshold")
            }
            if let useMultiChannel {
                formData.append(Data(String(useMultiChannel).utf8), withName: "use_multi_channel")
            }
            if let seed {
                formData.append(Data(String(seed).utf8), withName: "seed")
            }
            if let fileFormat, !fileFormat.isEmpty {
                formData.append(Data(fileFormat.utf8), withName: "file_format")
            }
            if let temperature {
                formData.append(Data(String(temperature).utf8), withName: "temperature")
            }
            if let noVerbatim {
                formData.append(Data(String(noVerbatim).utf8), withName: "no_verbatim")
            }
        }

        let (data, _) = try await networkManager.sendRequest(request)
        do {
            let decoded = try JSONDecoder.snakeCaseConverting().decode(TranscriptionResponse.self, from: data)
            return decoded.text ?? ""
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }
}
