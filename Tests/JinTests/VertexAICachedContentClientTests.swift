import Foundation
import XCTest
@testable import Jin

final class VertexAICachedContentClientTests: XCTestCase {
    override func tearDown() {
        VertexAITestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testListCachedContentsFollowsNextPageTokenUntilExhausted() async throws {
        let (configuration, protocolType) = makeVertexAITestSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let client = VertexAICachedContentClient(
            serviceAccountJSON: makeVertexCredentials(location: "us-central1"),
            networkManager: networkManager
        )
        var requestedPageTokens: [String?] = []

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-token")

            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let pageToken = components.queryItems?.first(where: { $0.name == "pageToken" })?.value
            requestedPageTokens.append(pageToken)

            let payloadObject: [String: Any]
            if pageToken == nil {
                payloadObject = [
                    "cachedContents": [
                        ["name": "projects/project/locations/us-central1/cachedContents/page-1"]
                    ],
                    "nextPageToken": "page-2-token"
                ]
            } else {
                XCTAssertEqual(pageToken, "page-2-token")
                payloadObject = [
                    "cachedContents": [
                        ["name": "projects/project/locations/us-central1/cachedContents/page-2"]
                    ]
                ]
            }

            let payload = try JSONSerialization.data(withJSONObject: payloadObject)
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload
            )
        }

        let resources = try await client.listCachedContents(accessToken: "vertex-token")

        XCTAssertEqual(requestedPageTokens, [nil, "page-2-token"])
        XCTAssertEqual(
            resources.map(\.name),
            [
                "projects/project/locations/us-central1/cachedContents/page-1",
                "projects/project/locations/us-central1/cachedContents/page-2"
            ]
        )
    }

    func testListCachedContentsStopsWhenNextPageTokenRepeats() async throws {
        let (configuration, protocolType) = makeVertexAITestSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let client = VertexAICachedContentClient(
            serviceAccountJSON: makeVertexCredentials(location: "us-central1"),
            networkManager: networkManager
        )
        var requestedPageTokens: [String?] = []

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")

            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let pageToken = components.queryItems?.first(where: { $0.name == "pageToken" })?.value
            requestedPageTokens.append(pageToken)

            let payloadObject: [String: Any]
            if pageToken == nil {
                payloadObject = [
                    "cachedContents": [
                        ["name": "projects/project/locations/us-central1/cachedContents/page-1"]
                    ],
                    "nextPageToken": "repeat-token"
                ]
            } else {
                XCTAssertEqual(pageToken, "repeat-token")
                payloadObject = [
                    "cachedContents": [
                        ["name": "projects/project/locations/us-central1/cachedContents/page-2"]
                    ],
                    "nextPageToken": "repeat-token"
                ]
            }

            let payload = try JSONSerialization.data(withJSONObject: payloadObject)
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload
            )
        }

        let resources = try await client.listCachedContents(accessToken: "vertex-token")

        XCTAssertEqual(requestedPageTokens, [nil, "repeat-token"])
        XCTAssertEqual(
            resources.map(\.name),
            [
                "projects/project/locations/us-central1/cachedContents/page-1",
                "projects/project/locations/us-central1/cachedContents/page-2"
            ]
        )
    }

    func testUpdateCachedContentBuildsPatchEndpointWithUpdateMask() async throws {
        let (configuration, protocolType) = makeVertexAITestSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)
        let client = VertexAICachedContentClient(
            serviceAccountJSON: makeVertexCredentials(location: "us-central1"),
            networkManager: networkManager
        )

        protocolType.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://us-central1-aiplatform.googleapis.com/v1/projects/project/locations/us-central1/cachedContents/my-cache?updateMask=ttl"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-token")

            let payload = try JSONSerialization.data(withJSONObject: [
                "name": "projects/project/locations/us-central1/cachedContents/my-cache",
                "expireTime": "2026-03-31T00:00:00Z"
            ])
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload
            )
        }

        let resource = try await client.updateCachedContent(
            named: "my-cache",
            payload: ["ttl": "3600s"],
            updateMask: "ttl",
            accessToken: "vertex-token"
        )

        XCTAssertEqual(resource.name, "projects/project/locations/us-central1/cachedContents/my-cache")
    }

    func testCachedContentEndpointPreservesFullyQualifiedNames() throws {
        let client = VertexAICachedContentClient(
            serviceAccountJSON: makeVertexCredentials(location: "global"),
            networkManager: NetworkManager()
        )

        let endpoint = try client.cachedContentURL(named: "projects/custom/locations/global/cachedContents/existing").absoluteString
        XCTAssertEqual(
            endpoint,
            "https://aiplatform.googleapis.com/v1/projects/custom/locations/global/cachedContents/existing"
        )
    }
}
