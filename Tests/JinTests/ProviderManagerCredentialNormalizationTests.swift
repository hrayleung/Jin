import Foundation
import XCTest
@testable import Jin

final class ProviderManagerCredentialNormalizationTests: XCTestCase {
    override func tearDown() {
        ProviderCredentialMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testValidateConfigurationTrimsAPIKeyBeforeAdapterValidation() async throws {
        let (configuration, protocolType) = makeProviderCredentialSessionConfiguration()
        let manager = ProviderManager(networkManager: NetworkManager(configuration: configuration))

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-provider-token")

            let payload = try JSONSerialization.data(withJSONObject: ["data": []])
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload
            )
        }

        let isValid = try await manager.validateConfiguration(
            for: ProviderConfig(
                id: "openai",
                name: "OpenAI",
                type: .openai,
                apiKey: " \n sk-provider-token\t ",
                baseURL: "https://api.example.test/v1"
            )
        )

        XCTAssertTrue(isValid)
    }

    func testCreateAdapterTrimsServiceAccountJSONBeforeDecoding() async throws {
        let credentials = makeVertexCredentials(location: "us-central1")
        let credentialsData = try JSONEncoder().encode(credentials)
        let credentialsJSON = try XCTUnwrap(String(data: credentialsData, encoding: .utf8))

        let manager = ProviderManager()
        let adapter = try await manager.createAdapter(
            for: ProviderConfig(
                id: "vertex",
                name: "Vertex AI",
                type: .vertexai,
                serviceAccountJSON: " \n\(credentialsJSON)\t "
            )
        )

        XCTAssertTrue(adapter is VertexAIAdapter)
    }
}

private final class ProviderCredentialMockURLProtocol: URLProtocol {
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

private func makeProviderCredentialSessionConfiguration() -> (
    URLSessionConfiguration,
    ProviderCredentialMockURLProtocol.Type
) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ProviderCredentialMockURLProtocol.self]
    return (config, ProviderCredentialMockURLProtocol.self)
}
