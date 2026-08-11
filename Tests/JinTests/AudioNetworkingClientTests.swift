import XCTest
@testable import Jin

final class AudioNetworkingClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.requestHandler = nil
    }

    private func whisperCapabilities() -> SpeechTranscriptionCapabilities {
        SpeechModelCapabilityRegistry.transcriptionCapabilities(provider: .openai, modelID: "whisper-1")
    }

    func testOpenAICompatibleAudioFieldsOmitBlankOptionalTextFields() {
        let fields = OpenAICompatibleAudioClientSupport.transcriptionFields(
            model: "whisper-1",
            capabilities: whisperCapabilities(),
            language: " ",
            prompt: "\n",
            responseFormat: "\t",
            temperature: nil,
            timestampGranularities: nil
        )

        // A blank stored `response_format` still resolves to the model's default.
        XCTAssertEqual(fields.map(\.name), ["model", "response_format"])
        XCTAssertEqual(fields.last?.value, "json")
    }

    /// `gpt-transcribe` takes `languages[]` and `keywords[]`, and rejects the singular
    /// `language`, `temperature`, subtitle formats and timestamps.
    func testGPTTranscribeFieldsUseLanguagesAndDropUnsupportedParameters() {
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .openai,
            modelID: "gpt-transcribe"
        )

        let fields = OpenAICompatibleAudioClientSupport.transcriptionFields(
            model: "gpt-transcribe",
            capabilities: capabilities,
            language: "en, fr",
            keywords: ["Jin", "SwiftData"],
            prompt: "A product demo",
            responseFormat: "verbose_json",
            temperature: 0.5,
            timestampGranularities: ["word"]
        )

        let names = fields.map(\.name)
        XCTAssertFalse(names.contains("language"))
        XCTAssertFalse(names.contains("temperature"))
        XCTAssertFalse(names.contains("timestamp_granularities[]"))
        XCTAssertEqual(names.filter { $0 == "languages[]" }.count, 2)
        XCTAssertEqual(names.filter { $0 == "keywords[]" }.count, 2)
        XCTAssertTrue(names.contains("prompt"))
        // verbose_json is clamped to the only format the model returns.
        XCTAssertEqual(fields.first { $0.name == "response_format" }?.value, "json")
    }

    func testWhisperFieldsKeepTimestampsAndTemperature() {
        let fields = OpenAICompatibleAudioClientSupport.transcriptionFields(
            model: "whisper-1",
            capabilities: whisperCapabilities(),
            language: "en",
            prompt: "hello",
            responseFormat: "srt",
            temperature: 0.5,
            timestampGranularities: ["word", "segment"]
        )

        let names = fields.map(\.name)
        XCTAssertTrue(names.contains("language"))
        XCTAssertTrue(names.contains("temperature"))
        XCTAssertEqual(names.filter { $0 == "timestamp_granularities[]" }.count, 2)
        XCTAssertEqual(fields.first { $0.name == "response_format" }?.value, "srt")
    }

    /// Mistral rejects a language hint and timestamps in the same request.
    func testMistralFieldsDropLanguageWhenTimestampsRequested() {
        let capabilities = SpeechModelCapabilityRegistry.transcriptionCapabilities(
            provider: .mistral,
            modelID: "voxtral-mini-transcribe-2602"
        )

        let fields = OpenAICompatibleAudioClientSupport.transcriptionFields(
            model: "voxtral-mini-transcribe-2602",
            capabilities: capabilities,
            language: "en",
            prompt: nil,
            responseFormat: "json",
            temperature: nil,
            timestampGranularities: ["segment"],
            diarize: true
        )

        let names = fields.map(\.name)
        XCTAssertFalse(names.contains("language"))
        XCTAssertTrue(names.contains("timestamp_granularities[]"))
        XCTAssertEqual(fields.first { $0.name == "diarize" }?.value, "true")
    }

    func testOpenAICompatibleAudioResponseFormatIsTrimmedBeforeDecoding() throws {
        let text = try OpenAICompatibleAudioClientSupport.decodeTranscriptionResponse(
            Data("{\"text\":\"Hello\"}".utf8),
            responseFormat: " JSON\n"
        )

        XCTAssertEqual(text, "Hello")
    }

    func testOpenAIAudioClientCreateSpeechBuildsJSONRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/audio/speech")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(json["model"] as? String, "gpt-4o-mini-tts")
            XCTAssertEqual(json["input"] as? String, "Hello")
            XCTAssertEqual(json["voice"] as? String, "alloy")
            XCTAssertEqual(json["response_format"] as? String, "wav")
            XCTAssertEqual((json["speed"] as? NSNumber)?.doubleValue, 1.25)
            XCTAssertEqual(json["instructions"] as? String, "Speak calmly")
            XCTAssertEqual(json["stream_format"] as? String, "sse")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("AUDIO".utf8)
            )
        }

        let client = OpenAIAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        let data = try await client.createSpeech(
            input: "Hello",
            model: "gpt-4o-mini-tts",
            voice: "alloy",
            responseFormat: "wav",
            speed: 1.25,
            instructions: "Speak calmly",
            streamFormat: "sse"
        )

        XCTAssertEqual(data, Data("AUDIO".utf8))
    }

    func testOpenAIAudioClientCreateTranscriptionBuildsMultipartRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/audio/transcriptions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

            let body = String(decoding: try XCTUnwrap(requestBodyData(request)), as: UTF8.self)
            XCTAssertTrue(body.contains("name=\"file\"; filename=\"clip.wav\""))
            XCTAssertTrue(body.contains("Content-Type: audio/wav"))
            XCTAssertTrue(body.contains("AUDIO"))
            XCTAssertTrue(body.contains("name=\"model\""))
            XCTAssertTrue(body.contains("whisper-1"))
            XCTAssertTrue(body.contains("name=\"language\""))
            XCTAssertTrue(body.contains("en"))
            XCTAssertTrue(body.contains("name=\"prompt\""))
            XCTAssertTrue(body.contains("Please transcribe"))
            XCTAssertTrue(body.contains("name=\"response_format\""))
            XCTAssertTrue(body.contains("json"))
            XCTAssertTrue(body.contains("name=\"temperature\""))
            XCTAssertTrue(body.contains("0.5"))
            XCTAssertEqual(body.components(separatedBy: "name=\"timestamp_granularities[]\"").count - 1, 2)

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"text\":\"Hello world\"}".utf8)
            )
        }

        let client = OpenAIAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        let text = try await client.createTranscription(
            fileData: Data("AUDIO".utf8),
            filename: "clip.wav",
            mimeType: "audio/wav",
            model: "whisper-1",
            capabilities: whisperCapabilities(),
            language: "en",
            prompt: "Please transcribe",
            responseFormat: "json",
            temperature: 0.5,
            timestampGranularities: ["word", "segment"]
        )

        XCTAssertEqual(text, "Hello world")
    }

    func testGroqAudioClientCreateTranslationReturnsRawTextForTextFormats() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/openai/v1/audio/translations")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

            let body = String(decoding: try XCTUnwrap(requestBodyData(request)), as: UTF8.self)
            XCTAssertTrue(body.contains("name=\"file\"; filename=\"clip.wav\""))
            XCTAssertTrue(body.contains("name=\"model\""))
            XCTAssertTrue(body.contains("whisper-large-v3"))
            XCTAssertTrue(body.contains("name=\"prompt\""))
            XCTAssertTrue(body.contains("Translate politely"))
            XCTAssertTrue(body.contains("name=\"response_format\""))
            XCTAssertTrue(body.contains("vtt"))
            XCTAssertTrue(body.contains("name=\"temperature\""))
            XCTAssertTrue(body.contains("0.2"))

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n".utf8)
            )
        }

        let client = GroqAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/openai/v1")!,
            networkManager: networkManager
        )

        let text = try await client.createTranslation(
            fileData: Data("AUDIO".utf8),
            filename: "clip.wav",
            mimeType: "audio/wav",
            model: "whisper-large-v3",
            prompt: "Translate politely",
            responseFormat: "vtt",
            temperature: 0.2
        )

        XCTAssertEqual(text, "WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n")
    }

    func testOpenAIAudioClientListModelsDecodesAvailableModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "data": [
                    { "id": "gpt-4o-mini-tts", "name": "GPT-4o mini TTS" },
                    { "id": "tts-1" }
                  ]
                }
                """.utf8)
            )
        }

        let client = OpenAIAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        let models = try await client.listModels()

        XCTAssertEqual(
            models,
            [
                SpeechProviderModelChoice(id: "gpt-4o-mini-tts", name: "GPT-4o mini TTS"),
                SpeechProviderModelChoice(id: "tts-1")
            ]
        )
    }

    func testGroqAudioClientListModelsDecodesAvailableModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/openai/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "data": [
                    { "id": "canopylabs/orpheus-v1-english", "name": "Orpheus English" },
                    { "id": "llama-3.3-70b-versatile", "name": "Llama" }
                  ]
                }
                """.utf8)
            )
        }

        let client = GroqAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/openai/v1")!,
            networkManager: networkManager
        )

        let models = try await client.listModels()

        XCTAssertEqual(
            models,
            [
                SpeechProviderModelChoice(id: "canopylabs/orpheus-v1-english", name: "Orpheus English"),
                SpeechProviderModelChoice(id: "llama-3.3-70b-versatile", name: "Llama")
            ]
        )
    }

    func testMiMoAudioClientListModelsFiltersToTTSModelIDs() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "test-key")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "data": [
                    { "id": "mimo-v2.5", "name": "MiMo V2.5" },
                    { "id": "mimo-v2.5-tts", "name": "MiMo V2.5 TTS" },
                    { "id": "mimo-v2.5-pro", "name": "MiMo V2.5 Pro" },
                    { "id": "mimo-v2.5-tts-voiceclone", "name": "MiMo V2.5 VoiceClone" },
                    { "id": "mimo-v2-tts", "name": "MiMo V2 TTS" }
                  ]
                }
                """.utf8)
            )
        }

        let client = MiMoAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        let models = try await client.listModels()

        // mimo-v2-tts went offline on 2026-06-30 and must not reach the picker.
        XCTAssertEqual(
            models,
            [
                SpeechProviderModelChoice(id: "mimo-v2.5-tts", name: "MiMo V2.5 TTS"),
                SpeechProviderModelChoice(id: "mimo-v2.5-tts-voiceclone", name: "MiMo V2.5 VoiceClone")
            ]
        )
    }

    func testMiMoAudioClientRejectsNonTTSModelBeforeRequest() async {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        var didMakeRequest = false

        protocolType.requestHandler = { request in
            didMakeRequest = true
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = MiMoAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        await XCTAssertThrowsErrorAsync({
            try await client.createSpeech(input: "Hello", model: "mimo-v2.5")
        }) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("MiMo TTS does not support model"))
            XCTAssertTrue(message.contains("mimo-v2.5"))
        }

        XCTAssertFalse(didMakeRequest)
    }

    func testElevenLabsTTSClientCreateSpeechOmitsBlankOutputFormatQuery() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "example.com")
            XCTAssertEqual(request.url?.path, "/v1/text-to-speech/voice-1")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            XCTAssertFalse(queryItems.contains { $0.name == "output_format" })
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "optimize_streaming_latency", value: "2")))
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "enable_logging", value: "false")))

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["text"] as? String, "Hello")
            XCTAssertEqual(json["model_id"] as? String, "eleven_multilingual_v2")
            XCTAssertEqual(json["language_code"] as? String, "en")
            XCTAssertEqual((json["seed"] as? NSNumber)?.intValue, 42)

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("AUDIO".utf8)
            )
        }

        let client = ElevenLabsTTSClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        let data = try await client.createSpeech(
            text: "Hello",
            voiceId: "voice-1",
            modelId: "eleven_multilingual_v2",
            outputFormat: " \n ",
            optimizeStreamingLatency: 2,
            enableLogging: false,
            languageCode: "en",
            seed: 42
        )

        XCTAssertEqual(data, Data("AUDIO".utf8))
    }

    func testOpenRouterAudioClientCreateSpeechBuildsJSONRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.example/api/v1/audio/speech")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Jin")
            XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://jin.app")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(json["model"] as? String, "google/gemini-3.1-flash-tts-preview")
            XCTAssertEqual(json["input"] as? String, "Hello")
            XCTAssertEqual(json["voice"] as? String, "Zephyr")
            XCTAssertEqual(json["response_format"] as? String, "mp3")
            XCTAssertEqual((json["speed"] as? NSNumber)?.doubleValue, 1.1)
            XCTAssertNil(json["instructions"])
            XCTAssertNil(json["stream_format"])
            // OpenRouter's speech schema has no `instructions`, and it no longer serves any
            // OpenAI TTS model, so the provider-options passthrough is gone.
            XCTAssertNil(json["provider"])

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("AUDIO".utf8)
            )
        }

        let client = OpenRouterAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://openrouter.example/api/v1")!,
            networkManager: networkManager
        )

        let data = try await client.createSpeech(
            input: "Hello",
            model: "google/gemini-3.1-flash-tts-preview",
            voice: "Zephyr",
            responseFormat: "mp3",
            speed: 1.1
        )

        XCTAssertEqual(data, Data("AUDIO".utf8))
    }

    /// The schema requires a non-empty voice when the key is present.
    func testOpenRouterAudioClientCreateSpeechOmitsBlankVoice() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(json["model"] as? String, "minimax/speech-2.8-hd")
            XCTAssertNil(json["voice"])

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("AUDIO".utf8)
            )
        }

        let client = OpenRouterAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://openrouter.example/api/v1")!,
            networkManager: networkManager
        )

        _ = try await client.createSpeech(
            input: "Hello",
            model: "minimax/speech-2.8-hd",
            voice: "  "
        )
    }

    func testOpenRouterSpeechModelsDecodeSupportedVoices() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://openrouter.example/api/v1/models?output_modalities=speech"
            )

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "data": [
                    {
                      "id": "google/gemini-3.1-flash-tts-preview",
                      "name": "Google: Gemini 3.1 Flash TTS Preview",
                      "supported_voices": ["Zephyr", "Puck", " "]
                    },
                    {
                      "id": "minimax/speech-2.8-hd",
                      "name": "MiniMax: Speech 2.8 HD",
                      "supported_voices": null
                    }
                  ]
                }
                """.utf8)
            )
        }

        let client = OpenRouterAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://openrouter.example/api/v1")!,
            networkManager: networkManager
        )

        let models = try await client.listSpeechModelsWithVoices()

        XCTAssertEqual(models.map(\.id), [
            "google/gemini-3.1-flash-tts-preview",
            "minimax/speech-2.8-hd"
        ])
        XCTAssertEqual(models[0].supportedVoices, ["Zephyr", "Puck"])
        XCTAssertEqual(models[1].supportedVoices, [])
    }

    func testOpenRouterAudioClientCreateTranscriptionBuildsBase64JSONRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let audioBytes = Data("AUDIO".utf8)
        let expectedBase64 = audioBytes.base64EncodedString()

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.example/api/v1/audio/transcriptions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Jin")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(json["model"] as? String, "openai/whisper-1")
            XCTAssertEqual(json["language"] as? String, "en")
            XCTAssertEqual((json["temperature"] as? NSNumber)?.doubleValue, 0.3)

            let inputAudio = try XCTUnwrap(json["input_audio"] as? [String: Any])
            XCTAssertEqual(inputAudio["data"] as? String, expectedBase64)
            XCTAssertEqual(inputAudio["format"] as? String, "wav")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "text": "Hello world",
                  "usage": { "seconds": 1.5, "total_tokens": 12 }
                }
                """.utf8)
            )
        }

        let client = OpenRouterAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://openrouter.example/api/v1")!,
            networkManager: networkManager
        )

        let text = try await client.createTranscription(
            audioData: audioBytes,
            audioFormat: "wav",
            model: "openai/whisper-1",
            language: "en",
            temperature: 0.3
        )

        XCTAssertEqual(text, "Hello world")
    }

    func testOpenRouterAudioClientTranscriptionOmitsBlankOptionalFields() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(json["model"] as? String, "openai/whisper-1")
            XCTAssertNotNil(json["input_audio"])
            XCTAssertNil(json["language"])
            XCTAssertNil(json["temperature"])

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"text\":\"\"}".utf8)
            )
        }

        let client = OpenRouterAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://openrouter.example/api/v1")!,
            networkManager: networkManager
        )

        _ = try await client.createTranscription(
            audioData: Data("AUDIO".utf8),
            audioFormat: "wav",
            model: "openai/whisper-1",
            language: "  ",
            temperature: nil
        )
    }

    func testOpenRouterAudioClientListSpeechModelsAppendsSpeechFilter() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "output_modalities", value: "speech")))

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "data": [
                    { "id": "openai/gpt-4o-mini-tts-2025-12-15", "name": "OpenAI mini TTS" },
                    { "id": "google/gemini-3.1-flash-tts-preview" }
                  ]
                }
                """.utf8)
            )
        }

        let client = OpenRouterAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://openrouter.example/api/v1")!,
            networkManager: networkManager
        )

        let models = try await client.listSpeechModels()

        XCTAssertEqual(
            models,
            [
                SpeechProviderModelChoice(id: "openai/gpt-4o-mini-tts-2025-12-15", name: "OpenAI mini TTS"),
                SpeechProviderModelChoice(id: "google/gemini-3.1-flash-tts-preview")
            ]
        )
    }

    func testOpenRouterAudioClientListTranscriptionModelsAppendsTranscriptionFilter() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "output_modalities", value: "transcription")))

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "data": [
                    { "id": "openai/whisper-1", "name": "Whisper-1" }
                  ]
                }
                """.utf8)
            )
        }

        let client = OpenRouterAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://openrouter.example/api/v1")!,
            networkManager: networkManager
        )

        let models = try await client.listTranscriptionModels()

        XCTAssertEqual(models, [SpeechProviderModelChoice(id: "openai/whisper-1", name: "Whisper-1")])
    }

    func testElevenLabsSTTClientListModelsDecodesAvailableModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-key")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                [
                  { "model_id": "scribe_v2", "name": "Scribe v2" },
                  { "model_id": "scribe_realtime_v1", "name": "Scribe Realtime" }
                ]
                """.utf8)
            )
        }

        let client = ElevenLabsSTTClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        let models = try await client.listModels()

        XCTAssertEqual(
            models,
            [
                SpeechProviderModelChoice(id: "scribe_v2", name: "Scribe v2"),
                SpeechProviderModelChoice(id: "scribe_realtime_v1", name: "Scribe Realtime")
            ]
        )
    }

    // MARK: - Mistral TTS

    /// The voice is `voice_id`, not `voice`, and the audio comes back base64 in JSON rather
    /// than as raw bytes.
    func testMistralTTSClientCreateSpeechBuildsJSONRequestAndDecodesBase64Audio() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://mistral.example/v1/audio/speech")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(json["model"] as? String, "voxtral-mini-tts-2603")
            XCTAssertEqual(json["input"] as? String, "Hello")
            XCTAssertEqual(json["voice_id"] as? String, "0fda0527-d5e8-4996-bb0a-afd589ad3ce2")
            XCTAssertEqual(json["response_format"] as? String, "mp3")
            XCTAssertNil(json["voice"])

            let payload = ["audio_data": Data("AUDIO".utf8).base64EncodedString()]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: payload)
            )
        }

        let client = MistralTTSClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://mistral.example/v1")!,
            networkManager: networkManager
        )

        let data = try await client.createSpeech(
            input: "Hello",
            model: "voxtral-mini-tts-2603",
            voiceId: "0fda0527-d5e8-4996-bb0a-afd589ad3ce2",
            responseFormat: "mp3"
        )

        XCTAssertEqual(data, Data("AUDIO".utf8))
    }

    func testMistralTTSClientSurfacesMissingAudioData() async {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{}".utf8)
            )
        }

        let client = MistralTTSClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://mistral.example/v1")!,
            networkManager: networkManager
        )

        do {
            _ = try await client.createSpeech(input: "Hello", model: "voxtral-mini-tts-2603")
            XCTFail("Expected a decoding error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("did not contain audio data"))
        }
    }

    /// Mistral publishes no static preset table, so the picker has to be filled from here.
    func testMistralTTSClientListVoicesRequestsPresetsAndDecodesItems() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.path, "/v1/audio/voices")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "type" })?.value, "preset")

            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "items": [
                    {
                      "created_at": "2025-12-17T10:25:07.818693Z",
                      "id": "0fda0527-d5e8-4996-bb0a-afd589ad3ce2",
                      "name": "en_paul_neutral",
                      "user_id": null
                    }
                  ],
                  "page": 1,
                  "page_size": 200,
                  "total": 1,
                  "total_pages": 1
                }
                """.utf8)
            )
        }

        let client = MistralTTSClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://mistral.example/v1")!,
            networkManager: networkManager
        )

        let voices = try await client.listVoices()

        XCTAssertEqual(voices.map(\.id), ["0fda0527-d5e8-4996-bb0a-afd589ad3ce2"])
        XCTAssertEqual(voices.first?.name, "en_paul_neutral")
        XCTAssertNil(voices.first?.userId)
    }

    func testMistralTTSClientListModelsFiltersToVoxtralTTSModels() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "data": [
                    { "id": "mistral-large-latest" },
                    { "id": "voxtral-mini-tts-2603" },
                    { "id": "voxtral-mini-transcribe-2602" }
                  ]
                }
                """.utf8)
            )
        }

        let client = MistralTTSClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://mistral.example/v1")!,
            networkManager: networkManager
        )

        let models = try await client.listModels()
        XCTAssertEqual(models.map(\.id), ["voxtral-mini-tts-2603"])
    }

    // MARK: - Streaming synthesis

    func testOpenAIAudioClientStreamsSSEAudioDeltas() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let firstChunk = Data([0x01, 0x02])
        let secondChunk = Data([0x03, 0x04])

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["stream_format"] as? String, "sse")
            XCTAssertEqual(json["response_format"] as? String, "pcm")

            let sse = """
            data: {"type":"speech.audio.delta","audio":"\(firstChunk.base64EncodedString())"}

            data: {"type":"speech.audio.delta","audio":"\(secondChunk.base64EncodedString())"}

            data: {"type":"speech.audio.done","usage":{"input_tokens":4}}


            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(sse.utf8)
            )
        }

        let client = OpenAIAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        var received = Data()
        for try await chunk in try await client.createSpeechStream(
            input: "Hello",
            model: "gpt-4o-mini-tts",
            voice: "marin",
            responseFormat: "pcm"
        ) {
            received.append(chunk)
        }

        XCTAssertEqual(received, firstChunk + secondChunk)
    }

    func testMiMoAudioClientStreamsDeltaAudioChunks() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let chunk = Data([0x10, 0x20])

        protocolType.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["stream"] as? Bool, true)
            let audio = try XCTUnwrap(json["audio"] as? [String: Any])
            XCTAssertEqual(audio["format"] as? String, "pcm16")

            let sse = """
            data: {"choices":[{"delta":{"audio":{"data":"\(chunk.base64EncodedString())"}}}]}

            data: [DONE]


            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(sse.utf8)
            )
        }

        let client = MiMoAudioClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        var received = Data()
        for try await audio in try await client.createSpeechStream(
            input: "Hello",
            model: MiMoModelIDs.ttsV25,
            voice: "mimo_default",
            responseFormat: "pcm16"
        ) {
            received.append(audio)
        }

        XCTAssertEqual(received, chunk)
    }

    /// The streaming endpoint returns raw chunked bytes rather than SSE frames.
    func testElevenLabsTTSClientStreamUsesStreamPathAndPassesBytesThrough() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        protocolType.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.path, "/v1/text-to-speech/voice-1/stream")
            XCTAssertEqual(
                components.queryItems?.first(where: { $0.name == "output_format" })?.value,
                "pcm_24000"
            )

            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("PCMBYTES".utf8)
            )
        }

        let client = ElevenLabsTTSClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            networkManager: networkManager
        )

        var received = Data()
        for try await chunk in try await client.createSpeechStream(
            text: "Hello",
            voiceId: "voice-1",
            modelId: "eleven_v3",
            outputFormat: "pcm_24000"
        ) {
            received.append(chunk)
        }

        XCTAssertEqual(received, Data("PCMBYTES".utf8))
    }

    /// v3 rejects `speed`, so it must be absent rather than sent as null-ish default.
    func testElevenLabsVoiceSettingsOmitSpeedWhenNotProvided() throws {
        let settings = ElevenLabsTTSClient.VoiceSettings(
            stability: 0.5,
            similarityBoost: 0.75,
            style: 0.0,
            useSpeakerBoost: true
        )

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(settings)) as? [String: Any]
        )

        XCTAssertNil(json["speed"])
        XCTAssertEqual((json["stability"] as? NSNumber)?.doubleValue, 0.5)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockedSessionConfiguration() -> (URLSessionConfiguration, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (config, MockURLProtocol.self)
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @escaping @Sendable () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 16 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read < 0 {
            return nil
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data
}
