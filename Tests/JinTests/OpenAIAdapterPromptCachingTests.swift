import Foundation
import XCTest
@testable import Jin

final class OpenAIAdapterPromptCachingTests: XCTestCase {
    func testOpenAIAdapterSendsPromptCacheControlsAndParsesCachedTokens() async throws {
        let (session, protocolType) = makeOpenAIMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "openai",
            name: "OpenAI",
            type: .openai,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(openAIRequestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(root["prompt_cache_key"] as? String, "stable-prefix")
            XCTAssertEqual(root["prompt_cache_retention"] as? String, "1h")
            XCTAssertEqual(root["prompt_cache_min_tokens"] as? Int, 1024)

            let response: [String: Any] = [
                "id": "resp_1",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "ok"]
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 12,
                    "output_tokens": 3,
                    "prompt_tokens_details": [
                        "cached_tokens": 8
                    ],
                    "output_tokens_details": [
                        "reasoning_tokens": 1
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(
                contextCache: ContextCacheControls(
                    mode: .implicit,
                    ttl: .hour1,
                    cacheKey: "stable-prefix",
                    minTokensThreshold: 1024
                )
            ),
            tools: [],
            streaming: false
        )

        var finalUsage: Usage?
        for try await event in stream {
            if case .messageEnd(let usage) = event {
                finalUsage = usage
            }
        }

        XCTAssertEqual(finalUsage?.inputTokens, 12)
        XCTAssertEqual(finalUsage?.outputTokens, 3)
        XCTAssertEqual(finalUsage?.thinkingTokens, 1)
        XCTAssertEqual(finalUsage?.cachedTokens, 8)
    }
}

private final class OpenAIPromptCachingMockURLProtocol: URLProtocol {
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

private func makeOpenAIMockedURLSession() -> (URLSession, OpenAIPromptCachingMockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [OpenAIPromptCachingMockURLProtocol.self]
    return (URLSession(configuration: config), OpenAIPromptCachingMockURLProtocol.self)
}

private func openAIRequestBodyData(_ request: URLRequest) -> Data? {
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
        if read <= 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data
}
