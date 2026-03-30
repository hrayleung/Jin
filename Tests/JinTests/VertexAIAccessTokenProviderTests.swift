import Foundation
import XCTest
@testable import Jin

final class VertexAIAccessTokenProviderTests: XCTestCase {
    override func tearDown() {
        VertexAITestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testAccessTokenProviderCachesTokenUntilNearExpiry() async throws {
        let (configuration, protocolType) = makeVertexAITestSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let provider = VertexAIAccessTokenProvider(
            serviceAccountJSON: makeVertexCredentials(),
            networkManager: networkManager
        )
        var requestCount = 0

        protocolType.requestHandler = { request in
            requestCount += 1
            XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
            XCTAssertEqual(request.httpMethod, "POST")

            let payload = try JSONSerialization.data(withJSONObject: [
                "access_token": "vertex-test-token",
                "expires_in": 3600,
                "token_type": "Bearer"
            ])
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload
            )
        }

        let first = try await provider.accessToken()
        let second = try await provider.accessToken()

        XCTAssertEqual(first, "vertex-test-token")
        XCTAssertEqual(second, "vertex-test-token")
        XCTAssertEqual(requestCount, 1)
    }
}
