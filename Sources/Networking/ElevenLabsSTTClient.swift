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
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode([AvailableModel].self, from: data).map { model in
                SpeechProviderModelChoice(id: model.modelId, name: model.name)
            }
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }

    /// 100ms silent 16-bit PCM WAV at 16kHz (meets ElevenLabs minimum).
    private static func minimalSilentWAV() -> Data {
        let sampleRate: UInt32 = 16_000
        let numSamples: UInt32 = 1_600 // 100ms
        let dataSize = numSamples * 2
        let chunkSize = 36 + dataSize
        var d = Data(capacity: Int(44 + dataSize))
        func u16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
        d.append(contentsOf: [0x52,0x49,0x46,0x46]); u32(chunkSize)
        d.append(contentsOf: [0x57,0x41,0x56,0x45])
        d.append(contentsOf: [0x66,0x6D,0x74,0x20]); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append(contentsOf: [0x64,0x61,0x74,0x61]); u32(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
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
            if let timestampsGranularity, !timestampsGranularity.isEmpty {
                formData.append(Data(timestampsGranularity.utf8), withName: "timestamps_granularity")
            }
            if let diarize {
                formData.append(Data(String(diarize).utf8), withName: "diarize")
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
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(TranscriptionResponse.self, from: data)
            return decoded.text ?? ""
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }
}
