import Foundation
import XCTest
@testable import Jin

final class GitHubModelsAdapterTests: XCTestCase {
    func testGitHubCopilotFetchAvailableModelsUsesCatalogEndpointAndMapsCapabilities() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

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
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
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

}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
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
