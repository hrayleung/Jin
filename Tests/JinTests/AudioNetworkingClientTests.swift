import XCTest
@testable import Jin

final class AudioNetworkingClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.requestHandler = nil
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
