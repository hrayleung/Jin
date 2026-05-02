import Foundation
import Alamofire

actor MiMoAudioClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://token-plan-sgp.xiaomimimo.com/v1")!
        static let defaultVoice = "mimo_default"
        static let defaultModel = MiMoModelIDs.ttsV25
        static let defaultResponseFormat = "wav"
        static let maxVoiceCloneSampleBase64Bytes = 10_000_000
    }

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct AudioOptions: Encodable {
        let format: String
        let voice: String?
    }

    private struct SpeechRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let audio: AudioOptions
    }

    private struct SpeechResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                struct Audio: Decodable {
                    let data: String?
                }

                let audio: Audio?
            }

            let message: Message?
        }

        let choices: [Choice]
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
            headers: miMoHeaders()
        )

        _ = try await networkManager.sendRequest(request)
    }

    func listModels(timeoutSeconds: TimeInterval = 30) async throws -> [SpeechProviderModelChoice] {
        let request = NetworkRequestFactory.makeRequest(
            url: baseURL.appendingPathComponent("models"),
            method: .get,
            timeoutSeconds: timeoutSeconds,
            headers: miMoHeaders()
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let models = try OpenAICompatibleAudioClientSupport.decodeAvailableModels(data)
        return SpeechProviderModelCatalog.textToSpeechChoices(
            for: .xiaomiMiMo,
            availableModels: models
        )
    }

    func createSpeech(
        input: String,
        model: String,
        voice: String? = nil,
        responseFormat: String? = nil,
        styleInstruction: String? = nil,
        voiceCloneSampleURL: URL? = nil,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> Data {
        let requestedModel = normalizedTrimmedString(model) ?? Constants.defaultModel
        let normalizedModel = requestedModel.lowercased()
        guard MiMoModelIDs.isTextToSpeechModelID(normalizedModel) else {
            throw LLMError.invalidRequest(message: "MiMo TTS does not support model “\(requestedModel)”.")
        }
        let format = normalizedTrimmedString(responseFormat) ?? Constants.defaultResponseFormat
        let style = normalizedTrimmedString(styleInstruction)

        var messages: [ChatMessage] = []
        if let style {
            messages.append(ChatMessage(role: "user", content: style))
        } else if normalizedModel == MiMoModelIDs.ttsV25VoiceDesign {
            throw SpeechExtensionError.missingMiMoVoiceDesignPrompt
        }
        messages.append(ChatMessage(role: "assistant", content: input))

        let resolvedVoice = try voiceValue(
            model: normalizedModel,
            configuredVoice: voice,
            voiceCloneSampleURL: voiceCloneSampleURL
        )
        let body = SpeechRequest(
            model: normalizedModel,
            messages: messages,
            audio: AudioOptions(format: format, voice: resolvedVoice)
        )

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: baseURL.appendingPathComponent("chat/completions"),
            timeoutSeconds: timeoutSeconds,
            headers: miMoHeaders(),
            body: body
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return try decodeAudioData(from: data)
    }

    private func miMoHeaders() -> HTTPHeaders {
        HTTPHeaders([
            HTTPHeader(name: "api-key", value: apiKey)
        ])
    }

    private func voiceValue(
        model: String,
        configuredVoice: String?,
        voiceCloneSampleURL: URL?
    ) throws -> String? {
        switch model {
        case MiMoModelIDs.ttsV25VoiceDesign:
            return nil
        case MiMoModelIDs.ttsV25VoiceClone:
            guard let voiceCloneSampleURL else {
                throw SpeechExtensionError.missingMiMoVoiceCloneSample
            }
            return try voiceCloneDataURI(from: voiceCloneSampleURL)
        default:
            return normalizedTrimmedString(configuredVoice) ?? Constants.defaultVoice
        }
    }

    private func voiceCloneDataURI(from url: URL) throws -> String {
        guard url.isFileURL else {
            throw SpeechExtensionError.invalidMiMoVoiceCloneSample("Choose a local mp3 or wav sample.")
        }

        let ext = url.pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "mp3":
            mimeType = "audio/mpeg"
        case "wav":
            mimeType = "audio/wav"
        default:
            throw SpeechExtensionError.invalidMiMoVoiceCloneSample("Voice cloning supports mp3 and wav samples only.")
        }

        let data = try resolveFileData(from: url)
        let base64 = data.base64EncodedString()
        guard base64.utf8.count <= Constants.maxVoiceCloneSampleBase64Bytes else {
            throw SpeechExtensionError.invalidMiMoVoiceCloneSample("Voice clone sample exceeds the documented 10 MB base64 limit.")
        }
        return "data:\(mimeType);base64,\(base64)"
    }

    private func decodeAudioData(from data: Data) throws -> Data {
        do {
            let decoded = try JSONDecoder().decode(SpeechResponse.self, from: data)
            guard let encodedAudio = decoded.choices.first?.message?.audio?.data,
                  let audioData = Data(base64Encoded: encodedAudio) else {
                throw LLMError.decodingError(message: "MiMo response did not contain audio data.")
            }
            return audioData
        } catch let error as LLMError {
            throw error
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }
}
