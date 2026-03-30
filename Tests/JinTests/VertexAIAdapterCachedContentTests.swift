import Foundation
import XCTest
@testable import Jin

final class VertexAIAdapterCachedContentTests: XCTestCase {
    override func tearDown() {
        VertexAITestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testListCachedContentsUsesCollectionEndpointAndAuthHeader() async throws {
        let adapter = makeCachedContentAdapter(location: "us-central1")
        var sawListRequest = false

        VertexAITestURLProtocol.requestHandler = { request in
            if let tokenResponse = try self.respondToTokenRequest(request) {
                return tokenResponse
            }

            sawListRequest = true
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://us-central1-aiplatform.googleapis.com/v1/projects/project/locations/us-central1/cachedContents"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let payload = try self.makeCachedContentsListPayload(names: [
                "projects/project/locations/us-central1/cachedContents/cache-a"
            ])
            return try self.makeSuccessResponse(for: request, body: payload)
        }

        let resources = try await adapter.listCachedContents()

        XCTAssertTrue(sawListRequest)
        XCTAssertEqual(resources.map(\.name), ["projects/project/locations/us-central1/cachedContents/cache-a"])
    }

    func testGetCachedContentUsesShortNameEndpoint() async throws {
        let adapter = makeCachedContentAdapter(location: "us-central1")

        VertexAITestURLProtocol.requestHandler = { request in
            if let tokenResponse = try self.respondToTokenRequest(request) {
                return tokenResponse
            }

            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://us-central1-aiplatform.googleapis.com/v1/projects/project/locations/us-central1/cachedContents/my-cache"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let payload = try self.makeCachedContentPayload(
                name: "projects/project/locations/us-central1/cachedContents/my-cache"
            )
            return try self.makeSuccessResponse(for: request, body: payload)
        }

        let resource = try await adapter.getCachedContent(named: "my-cache")
        XCTAssertEqual(resource.name, "projects/project/locations/us-central1/cachedContents/my-cache")
    }

    func testGetCachedContentPreservesFullyQualifiedName() async throws {
        let adapter = makeCachedContentAdapter(location: "global")

        VertexAITestURLProtocol.requestHandler = { request in
            if let tokenResponse = try self.respondToTokenRequest(request) {
                return tokenResponse
            }

            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://aiplatform.googleapis.com/v1/projects/custom/locations/global/cachedContents/existing"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let payload = try self.makeCachedContentPayload(
                name: "projects/custom/locations/global/cachedContents/existing"
            )
            return try self.makeSuccessResponse(for: request, body: payload)
        }

        let resource = try await adapter.getCachedContent(
            named: "projects/custom/locations/global/cachedContents/existing"
        )
        XCTAssertEqual(resource.name, "projects/custom/locations/global/cachedContents/existing")
    }

    func testCreateCachedContentRejectsInvalidJSONPayload() async throws {
        let adapter = makeCachedContentAdapter()
        var requestCount = 0

        VertexAITestURLProtocol.requestHandler = { request in
            requestCount += 1
            if let tokenResponse = try self.respondToTokenRequest(request) {
                return tokenResponse
            }
            XCTFail("Expected invalid payload to stop before cached-content request")
            throw URLError(.badServerResponse)
        }

        await XCTAssertThrowsErrorAsync({
            try await adapter.createCachedContent(payload: ["invalid": Date()])
        }) { error in
            guard case let LLMError.invalidRequest(message) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, "Invalid cachedContent payload.")
        }

        XCTAssertEqual(requestCount, 1)
    }

    func testUpdateCachedContentIncludesUpdateMaskQueryItem() async throws {
        let adapter = makeCachedContentAdapter(location: "us-central1")

        VertexAITestURLProtocol.requestHandler = { request in
            if let tokenResponse = try self.respondToTokenRequest(request) {
                return tokenResponse
            }

            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://us-central1-aiplatform.googleapis.com/v1/projects/project/locations/us-central1/cachedContents/my-cache?updateMask=ttl"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-test-token")

            let body = try XCTUnwrap(vertexAIRequestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json, ["ttl": "3600s"])

            let payload = try self.makeCachedContentPayload(
                name: "projects/project/locations/us-central1/cachedContents/my-cache"
            )
            return try self.makeSuccessResponse(for: request, body: payload)
        }

        let resource = try await adapter.updateCachedContent(
            named: "my-cache",
            payload: ["ttl": "3600s"],
            updateMask: "ttl"
        )

        XCTAssertEqual(resource.name, "projects/project/locations/us-central1/cachedContents/my-cache")
    }

    func testDeleteCachedContentUsesDeleteAgainstCorrectEndpoint() async throws {
        let adapter = makeCachedContentAdapter(location: "us-central1")

        VertexAITestURLProtocol.requestHandler = { request in
            if let tokenResponse = try self.respondToTokenRequest(request) {
                return tokenResponse
            }

            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://us-central1-aiplatform.googleapis.com/v1/projects/project/locations/us-central1/cachedContents/my-cache"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-test-token")

            return try self.makeSuccessResponse(for: request, body: Data("{}".utf8))
        }

        try await adapter.deleteCachedContent(named: "my-cache")
    }

    private func makeCachedContentAdapter(location: String = "global") -> VertexAIAdapter {
        let (configuration, _) = makeVertexAITestSessionConfiguration()
        return VertexAIAdapter(
            providerConfig: makeVertexProviderConfig(),
            serviceAccountJSON: makeVertexCredentials(location: location),
            networkManager: NetworkManager(configuration: configuration)
        )
    }

    private func respondToTokenRequest(_ request: URLRequest) throws -> (HTTPURLResponse, Data)? {
        guard request.url?.absoluteString == "https://oauth2.googleapis.com/token" else {
            return nil
        }

        let payload = try JSONSerialization.data(withJSONObject: [
            "access_token": "vertex-test-token",
            "expires_in": 3600,
            "token_type": "Bearer",
        ])
        return try makeSuccessResponse(for: request, body: payload)
    }

    private func makeCachedContentsListPayload(names: [String]) throws -> Data {
        let cachedContents = names.map { ["name": $0] }
        return try JSONSerialization.data(withJSONObject: ["cachedContents": cachedContents])
    }

    private func makeCachedContentPayload(name: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["name": name])
    }

    private func makeSuccessResponse(for request: URLRequest, body: Data) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        return (try XCTUnwrap(response), body)
    }
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
