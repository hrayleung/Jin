import Foundation
import XCTest
@testable import Jin

final class GitHubModelsAdapterTests: XCTestCase {
    func testGitHubCopilotFetchAvailableModelsUsesCatalogEndpointAndMapsCapabilities() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)

        let providerConfig = ProviderConfig(
            id: "github-copilot",
            name: "GitHub Copilot",
            type: .githubCopilot,
            apiKey: "ignored",
            baseURL: "https://models.github.ai/inference"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://models.github.ai/catalog/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")

            let payload: [[String: Any]] = [
                [
                    "id": "openai/gpt-4o",
                    "name": "GPT-4o",
                    "supported_input_modalities": ["text", "image", "pdf"],
                    "supported_output_modalities": ["text"],
                    "capabilities": ["streaming", "tool-calling", "prompt-caching"],
                    "limits": [
                        "max_input_tokens": 128000,
                        "max_output_tokens": 16384
                    ],
                    "publisher": "OpenAI",
                    "summary": "Fast multimodal model",
                    "rate_limit_tier": "free"
                ],
                [
                    "id": "microsoft/phi-4-mini-reasoning",
                    "name": "Phi-4 mini reasoning",
                    "supported_input_modalities": ["text"],
                    "supported_output_modalities": ["text"],
                    "capabilities": ["reasoning"],
                    "tags": ["reasoning", "low latency"],
                    "limits": [
                        "max_input_tokens": 128000,
                        "max_output_tokens": 4096
                    ],
                    "publisher": "Microsoft"
                ],
                [
                    "id": "openai/text-embedding-3-small",
                    "name": "Text Embedding 3 Small",
                    "supported_input_modalities": ["text"],
                    "supported_output_modalities": ["embeddings"],
                    "capabilities": [],
                    "limits": [
                        "max_input_tokens": 8192,
                        "max_output_tokens": 8192
                    ]
                ]
            ]

            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-token", networkManager: networkManager)
        let models = try await adapter.fetchAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        XCTAssertEqual(models.count, 2)
        XCTAssertNil(byID["openai/text-embedding-3-small"])

        let gpt4o = try XCTUnwrap(byID["openai/gpt-4o"])
        XCTAssertEqual(gpt4o.contextWindow, 128_000)
        XCTAssertEqual(gpt4o.maxOutputTokens, 16_384)
        XCTAssertTrue(gpt4o.capabilities.contains(.streaming))
        XCTAssertTrue(gpt4o.capabilities.contains(.vision))
        XCTAssertTrue(gpt4o.capabilities.contains(.nativePDF))
        XCTAssertTrue(gpt4o.capabilities.contains(.toolCalling))
        XCTAssertTrue(gpt4o.capabilities.contains(.promptCaching))
        XCTAssertNotNil(gpt4o.catalogMetadata?.availabilityMessage)

        let phi = try XCTUnwrap(byID["microsoft/phi-4-mini-reasoning"])
        XCTAssertEqual(phi.contextWindow, 128_000)
        XCTAssertEqual(phi.maxOutputTokens, 4_096)
        XCTAssertTrue(phi.capabilities.contains(.reasoning))
        XCTAssertFalse(phi.capabilities.contains(.streaming))
        XCTAssertEqual(phi.reasoningConfig?.type, .effort)
    }

    func testGitHubCopilotValidateAPIKeyUsesCatalogEndpoint() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)
        let providerConfig = ProviderConfig(
            id: "github-copilot",
            name: "GitHub Copilot",
            type: .githubCopilot,
            apiKey: "ignored",
            baseURL: "https://models.github.ai/inference"
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://models.github.ai/catalog/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
            XCTAssertNil(request.httpBody)

            let data = try JSONSerialization.data(withJSONObject: [["id": "openai/gpt-4.1"]])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAICompatibleAdapter(providerConfig: providerConfig, apiKey: "test-token", networkManager: networkManager)
        let isValid = try await adapter.validateAPIKey("test-token")
        XCTAssertTrue(isValid)
    }

    func testGitHubDeviceFlowValidateAccessPreservesRateLimitError() async {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)
        let authenticator = GitHubDeviceFlowAuthenticator(networkManager: networkManager)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://models.github.ai/catalog/models")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "30"]
                )!,
                Data("rate limited".utf8)
            )
        }

        do {
            try await authenticator.validateGitHubModelsAccess(accessToken: "test-token")
            XCTFail("Expected rateLimitExceeded to be rethrown")
        } catch let error as LLMError {
            guard case .rateLimitExceeded(let retryAfter) = error else {
                return XCTFail("Expected rateLimitExceeded, got \(error)")
            }
            XCTAssertEqual(retryAfter, 30)
        } catch {
            XCTFail("Expected LLMError.rateLimitExceeded, got \(error)")
        }
    }

    func testGitHubDeviceFlowRequestDeviceCodeUsesExpectedEndpoint() async throws {
        let (session, protocolType) = makeMockedURLSession()
        let networkManager = NetworkManager(urlSession: session)
        let authenticator = GitHubDeviceFlowAuthenticator(networkManager: networkManager)

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/device/code")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            XCTAssertEqual(String(data: requestBodyData(request) ?? Data(), encoding: .utf8), "client_id=test-client")

            let payload: [String: Any] = [
                "device_code": "device-code",
                "user_code": "1A2B-3C4D",
                "verification_uri": "https://github.com/login/device",
                "expires_in": 900,
                "interval": 5
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let response = try await authenticator.requestDeviceCode(clientID: "test-client")
        XCTAssertEqual(response.deviceCode, "device-code")
        XCTAssertEqual(response.userCode, "1A2B-3C4D")
        XCTAssertEqual(response.verificationURI, "https://github.com/login/device")
        XCTAssertEqual(response.expiresIn, 900)
        XCTAssertEqual(response.interval, 5)
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

private func makeMockedURLSession() -> (URLSession, MockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return (URLSession(configuration: config), MockURLProtocol.self)
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
