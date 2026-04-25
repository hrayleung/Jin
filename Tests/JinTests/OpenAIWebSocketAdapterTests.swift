import Foundation
import XCTest
@testable import Jin

final class OpenAIWebSocketAdapterTests: XCTestCase {
    func testOpenAIWebSocketAdapterFetchModelsAddsNativePDFForVisionFamilies() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai-websocket",
            name: "OpenAI (WebSocket)",
            type: .openaiWebSocket,
            apiKey: "ignored",
            baseURL: "https://example.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let payload: [String: Any] = [
                "data": [
                    ["id": "gpt-5.2"],
                    ["id": "gpt-5.3-codex"],
                    ["id": "gpt-5.3-chat-latest"],
                    ["id": "gpt-4o"],
                    ["id": "gpt-4.1-mini"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIWebSocketAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let gpt52 = try XCTUnwrap(byID["gpt-5.2"])
        XCTAssertEqual(gpt52.contextWindow, 400_000)
        XCTAssertTrue(gpt52.capabilities.contains(.vision))
        XCTAssertTrue(gpt52.capabilities.contains(.reasoning))
        XCTAssertTrue(gpt52.capabilities.contains(.nativePDF))

        let gpt53 = try XCTUnwrap(byID["gpt-5.3-codex"])
        XCTAssertEqual(gpt53.contextWindow, 400_000)
        XCTAssertTrue(gpt53.capabilities.contains(.vision))
        XCTAssertTrue(gpt53.capabilities.contains(.reasoning))
        XCTAssertTrue(gpt53.capabilities.contains(.nativePDF))

        let gpt53ChatLatest = try XCTUnwrap(byID["gpt-5.3-chat-latest"])
        XCTAssertEqual(gpt53ChatLatest.contextWindow, 128_000)
        XCTAssertTrue(gpt53ChatLatest.capabilities.contains(.vision))
        XCTAssertFalse(gpt53ChatLatest.capabilities.contains(.reasoning))
        XCTAssertFalse(gpt53ChatLatest.capabilities.contains(.nativePDF))

        let gpt4o = try XCTUnwrap(byID["gpt-4o"])
        XCTAssertEqual(gpt4o.contextWindow, 128_000)
        XCTAssertTrue(gpt4o.capabilities.contains(.vision))
        XCTAssertFalse(gpt4o.capabilities.contains(.reasoning))
        XCTAssertTrue(gpt4o.capabilities.contains(.nativePDF))

        let gpt41mini = try XCTUnwrap(byID["gpt-4.1-mini"])
        XCTAssertFalse(gpt41mini.capabilities.contains(.nativePDF))
    }

    func testOpenAIWebSocketAdapterFetchModelsFiltersKnownNonStreamingGPT55ProIDs() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai-websocket",
            name: "OpenAI (WebSocket)",
            type: .openaiWebSocket,
            apiKey: "ignored",
            baseURL: "https://example.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")

            let payload: [String: Any] = [
                "data": [
                    ["id": "gpt-5.5"],
                    ["id": "gpt-5.5-pro"],
                    ["id": "gpt-5.5-pro-2026-04-23"],
                    ["id": "gpt-image-2"],
                    ["id": "custom-streaming-model"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIWebSocketAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let ids = Set(models.map(\.id))

        XCTAssertTrue(ids.contains("gpt-5.5"))
        XCTAssertTrue(ids.contains("gpt-image-2"))
        XCTAssertTrue(ids.contains("custom-streaming-model"))
        XCTAssertFalse(ids.contains("gpt-5.5-pro"))
        XCTAssertFalse(ids.contains("gpt-5.5-pro-2026-04-23"))
    }

    func testOpenAIWebSocketAdapterRejectsKnownIncompatibleSavedModelIDsBeforeRuntimeRouting() async {
        let adapter = OpenAIWebSocketAdapter(
            providerConfig: ProviderConfig(
                id: "openai-websocket",
                name: "OpenAI (WebSocket)",
                type: .openaiWebSocket,
                apiKey: "ignored",
                baseURL: "https://example.com/v1"
            ),
            apiKey: "test-key"
        )

        do {
            _ = try await adapter.sendMessage(
                messages: [Message(role: .user, content: [.text("hi")])],
                modelID: "gpt-5.5-pro",
                controls: GenerationControls(),
                tools: [],
                streaming: true
            )
            XCTFail("Expected gpt-5.5-pro to be rejected before WebSocket routing.")
        } catch let error as LLMError {
            guard case .invalidRequest(let message) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("gpt-5.5-pro"))
            XCTAssertTrue(message.contains("OpenAI provider"))
        } catch {
            XCTFail("Expected LLMError.invalidRequest, got \(error)")
        }
    }

    func testOpenAIWebSocketAdapterTreatsResponseIncompleteAsTerminalEvent() async {
        let adapter = OpenAIWebSocketAdapter(
            providerConfig: ProviderConfig(
                id: "openai-websocket",
                name: "OpenAI (WebSocket)",
                type: .openaiWebSocket,
                apiKey: "ignored",
                baseURL: "https://example.com/v1"
            ),
            apiKey: "test-key"
        )

        let isTerminal = await adapter.isTerminalResponseEventType("response.incomplete")
        XCTAssertTrue(isTerminal)
    }

    func testOpenAIWebSocketAdapterFetchModelsPreservesAudioMetadataForKnownAudioIDs() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "openai-websocket",
            name: "OpenAI (WebSocket)",
            type: .openaiWebSocket,
            apiKey: "ignored",
            baseURL: "https://example.com/v1"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            let payload: [String: Any] = [
                "data": [
                    ["id": "gpt-4o-audio-preview"],
                    ["id": "gpt-realtime-mini"],
                    ["id": "gpt-4.1-mini"]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIWebSocketAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        XCTAssertTrue(try XCTUnwrap(byID["gpt-4o-audio-preview"]).capabilities.contains(.audio))
        XCTAssertTrue(try XCTUnwrap(byID["gpt-realtime-mini"]).capabilities.contains(.audio))
        XCTAssertFalse(try XCTUnwrap(byID["gpt-4.1-mini"]).capabilities.contains(.audio))
    }

    func testResponseCreateEventPutsResponsesBodyAtTopLevel() throws {
        let responsePayload: [String: Any] = [
            "model": "gpt-5.2",
            "input": [
                [
                    "type": "message",
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": "hi"]
                    ]
                ]
            ],
            "previous_response_id": "resp_prev_123"
        ]

        let event = OpenAIWebSocketAdapter.responseCreateEvent(from: responsePayload)

        XCTAssertEqual(event["type"] as? String, "response.create")
        XCTAssertEqual(event["model"] as? String, "gpt-5.2")
        XCTAssertNotNil(event["input"])
        XCTAssertNil(event["response"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: event))
    }

    func testDecodeErrorEventPayloadExtractsCodeAndMessage() throws {
        let json = """
        {"type":"error","error":{"code":"invalid_request_error","message":"Bad request"}}
        """

        let err = OpenAIWebSocketAdapter.decodeErrorEventPayload(
            Data(json.utf8),
            fallbackMessage: "fallback"
        )

        guard case .providerError(let code, let message) = err else {
            return XCTFail("Expected providerError")
        }

        XCTAssertEqual(code, "invalid_request_error")
        XCTAssertEqual(message, "Bad request")
    }

    func testDecodeErrorEventPayloadFallsBackToTypeAndOuterMessage() throws {
        let json = """
        {"type":"error","error":{"type":"rate_limit","message":"Too many requests"}}
        """

        let err = OpenAIWebSocketAdapter.decodeErrorEventPayload(
            Data(json.utf8),
            fallbackMessage: "fallback"
        )

        guard case .providerError(let code, let message) = err else {
            return XCTFail("Expected providerError")
        }

        XCTAssertEqual(code, "rate_limit")
        XCTAssertEqual(message, "Too many requests")
    }

}

// MARK: - URLProtocol stubbing

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
