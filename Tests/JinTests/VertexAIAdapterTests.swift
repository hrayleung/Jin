import Foundation
import XCTest
@testable import Jin

final class VertexAIAdapterTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testVertexAIAdapterBuildsCodeExecutionToolAndParsesExecutionParts() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "vertex",
            name: "Vertex AI",
            type: .vertexai,
            apiKey: "ignored"
        )

        let credentials = ServiceAccountCredentials(
            type: "service_account",
            projectID: "project",
            privateKeyID: "key-id",
            privateKey: testVertexPrivateKey,
            clientEmail: "svc@example.com",
            clientID: "1234567890",
            authURI: "https://accounts.google.com/o/oauth2/auth",
            tokenURI: "https://oauth2.googleapis.com/token",
            authProviderX509CertURL: "https://www.googleapis.com/oauth2/v1/certs",
            clientX509CertURL: "https://www.googleapis.com/robot/v1/metadata/x509/svc%40example.com",
            location: "global"
        )

        protocolType.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.absoluteString == "https://oauth2.googleapis.com/token" {
                let payload = try JSONSerialization.data(withJSONObject: [
                    "access_token": "vertex-test-token",
                    "expires_in": 3600,
                    "token_type": "Bearer",
                ])
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
            }

            XCTAssertEqual(
                url.absoluteString,
                "https://aiplatform.googleapis.com/v1/projects/project/locations/global/publishers/google/models/gemini-2.5-flash:streamGenerateContent"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vertex-test-token")

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let root = try XCTUnwrap(json)
            let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])

            XCTAssertEqual(tools.count, 1)
            XCTAssertNotNil(tools.first?["codeExecution"])

            let responseLine = """
            {"candidates":[{"content":{"parts":[{"executableCode":{"language":"PYTHON","code":"print(2)"}},{"codeExecutionResult":{"outcome":"OUTCOME_FAILED","output":"Traceback"}}]}}]}

            """

            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(responseLine.utf8)
            )
        }

        let adapter = VertexAIAdapter(
            providerConfig: providerConfig,
            serviceAccountJSON: credentials,
            networkManager: networkManager
        )

        let stream = try await adapter.sendMessage(
            messages: [
                Message(role: .user, content: [.text("run vertex code")])
            ],
            modelID: "gemini-2.5-flash",
            controls: GenerationControls(codeExecution: CodeExecutionControls(enabled: true)),
            tools: [],
            streaming: true
        )

        var activities: [CodeExecutionActivity] = []
        for try await event in stream {
            if case .codeExecutionActivity(let activity) = event {
                activities.append(activity)
            }
        }

        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities.first?.status, .writingCode)
        XCTAssertEqual(activities.first?.code, "print(2)")
        XCTAssertEqual(activities.last?.status, .failed)
        XCTAssertEqual(activities.last?.stderr, "Traceback")
        XCTAssertEqual(activities.first?.id, activities.last?.id)
    }

    func testVertexAIAdapterBuildsGoogleMapsToolRequest() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "vertex-maps",
            name: "Vertex AI",
            type: .vertexai,
            apiKey: "ignored"
        )

        let credentials = ServiceAccountCredentials(
            type: "service_account",
            projectID: "project",
            privateKeyID: "key-id",
            privateKey: testVertexPrivateKey,
            clientEmail: "svc@example.com",
            clientID: "1234567890",
            authURI: "https://accounts.google.com/o/oauth2/auth",
            tokenURI: "https://oauth2.googleapis.com/token",
            authProviderX509CertURL: "https://www.googleapis.com/oauth2/v1/certs",
            clientX509CertURL: "https://www.googleapis.com/robot/v1/metadata/x509/svc%40example.com",
            location: "global"
        )

        protocolType.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.absoluteString == "https://oauth2.googleapis.com/token" {
                let payload = try JSONSerialization.data(withJSONObject: [
                    "access_token": "vertex-test-token",
                    "expires_in": 3600,
                    "token_type": "Bearer",
                ])
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
            }

            XCTAssertEqual(
                url.absoluteString,
                "https://aiplatform.googleapis.com/v1/projects/project/locations/global/publishers/google/models/gemini-2.5-flash:streamGenerateContent"
            )

            let body = try XCTUnwrap(requestBodyData(request))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
            XCTAssertEqual(tools.count, 1)

            let googleMaps = try XCTUnwrap(tools.first?["googleMaps"] as? [String: Any])
            XCTAssertEqual(googleMaps["enableWidget"] as? Bool, true)

            let toolConfig = try XCTUnwrap(json["toolConfig"] as? [String: Any])
            let retrievalConfig = try XCTUnwrap(toolConfig["retrievalConfig"] as? [String: Any])
            let latLng = try XCTUnwrap(retrievalConfig["latLng"] as? [String: Any])
            XCTAssertEqual(latLng["latitude"] as? Double, 34.050481)
            XCTAssertEqual(latLng["longitude"] as? Double, -118.248526)
            XCTAssertEqual(retrievalConfig["languageCode"] as? String, "en_US")

            let responseLine = """
            {"candidates":[{"content":{"parts":[{"text":"Maps answer"}]}}]}

            """

            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(responseLine.utf8)
            )
        }

        let adapter = VertexAIAdapter(
            providerConfig: providerConfig,
            serviceAccountJSON: credentials,
            networkManager: networkManager
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Find coffee near me")])],
            modelID: "gemini-2.5-flash",
            controls: GenerationControls(
                googleMaps: GoogleMapsControls(
                    enabled: true,
                    enableWidget: true,
                    latitude: 34.050481,
                    longitude: -118.248526,
                    languageCode: "en_US"
                )
            ),
            tools: [],
            streaming: true
        )

        for try await _ in stream {}
    }

    func testVertexAIAdapterSuppressesNativeGoogleSearchToolCallEvents() async throws {
        let (configuration, protocolType) = makeMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "vertex-native-search",
            name: "Vertex AI",
            type: .vertexai,
            apiKey: "ignored"
        )

        let credentials = ServiceAccountCredentials(
            type: "service_account",
            projectID: "project",
            privateKeyID: "key-id",
            privateKey: testVertexPrivateKey,
            clientEmail: "svc@example.com",
            clientID: "1234567890",
            authURI: "https://accounts.google.com/o/oauth2/auth",
            tokenURI: "https://oauth2.googleapis.com/token",
            authProviderX509CertURL: "https://www.googleapis.com/oauth2/v1/certs",
            clientX509CertURL: "https://www.googleapis.com/robot/v1/metadata/x509/svc%40example.com",
            location: "global"
        )

        protocolType.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.absoluteString == "https://oauth2.googleapis.com/token" {
                let payload = try JSONSerialization.data(withJSONObject: [
                    "access_token": "vertex-test-token",
                    "expires_in": 3600,
                    "token_type": "Bearer",
                ])
                return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
            }

            let responseLine = """
            {"candidates":[{"content":{"parts":[{"functionCall":{"name":"google_search","args":{"query":"cross the sea"}}},{"text":"Answer"}]},"groundingMetadata":{"webSearchQueries":["cross the sea"]}}]}

            """

            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(responseLine.utf8)
            )
        }

        let adapter = VertexAIAdapter(
            providerConfig: providerConfig,
            serviceAccountJSON: credentials,
            networkManager: networkManager
        )

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gemini-3-flash-preview",
            controls: GenerationControls(webSearch: WebSearchControls(enabled: true)),
            tools: [],
            streaming: true
        )

        var toolCalls: [ToolCall] = []
        var searchEvents: [SearchActivity] = []

        for try await event in stream {
            switch event {
            case .toolCallStart(let call), .toolCallEnd(let call):
                toolCalls.append(call)
            case .searchActivity(let activity):
                searchEvents.append(activity)
            default:
                break
            }
        }

        XCTAssertTrue(toolCalls.isEmpty)
        XCTAssertEqual(searchEvents.first?.arguments["query"]?.value as? String, "cross the sea")
    }
}

private let testVertexPrivateKey = """
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDA1fuTdbcrqnqP
4ut6qccSZozQT/WeeERtbQz+aDqAdR9LEDsfpO/y6Wp7m3VTmUSVPZKxHAMqmjai
8zB70uwhIUMTwVd2IvDGvw1wilMEPpyycD7qJyxCX7Mi0wRHk0Sddak8KlUWxAdu
1l9+c5IQfyH0xGFU6T45meK+6RbgVEohYrzbu9BcYOVO6tQFLRahoLjLq6VD5Z/G
55EKZvuGvj0vbXiLE6dPqcy81IGwLb79UJuKrmw6FmaCiVKvRGE6C86GtmZ5Fart
da5YTxrqi0kXEo+fy66FLAhqceRw11rVJBWnoUsDGk3/nCUr9qDsLYDZPVvEXElI
V2Eo2wExAgMBAAECggEAOnqKBQF9T2ovKeRsefHzs3JTALdG6sxZIAAioSI1n5Al
McvVyjZoJ/e+OYb+8R+5SzL1ge1XTnue1xK94McpobBnGZ4X6nUVJIh6yGbCXzan
qXtdsP+5LdW8yvJISXZxJ/kvHdZOoI1JHcU4B25/3K3ZO9O0Gp5zJt+ygifIrrWK
VFQ6S86gbaN2I5jX1By16AxTfjHxdYZyNu3D2kwJ/LS5VKkdkN33gDHymd0xTGwB
rb0r9AtkLXNtbLWg9PznuvhvfbAFkJ51oIj4NAcbbl98lDXq0jnQrP6zoTS9JsrH
Mv8/Mykv+x02VxFvnBrkHJ1B3ETbdEPbsSvt6Z3n4wKBgQDfo35EEo9ns2FbVJtf
rYRKtv/y00YoSFRfg+yYvRzCNGtKffdn6vxMVbDUBGiv9RX+cqV/NcMEoSPwhav/
aOhrxdT6mnX9ghAfT/E58DqSU9aslOkehHaIbKIOUbddkTEK9dp23RZT54REj7CJ
0F1GJdYvvjKuh4oP6MyG8g1XqwKBgQDcvW0pWxNaQy066hzq4PmUEyXqW72anY0r
0J/nwXUCpvYSAgtZztkkhvDkN29q1//3ZDo9bRybSKczJ2CFVAcNUTpLE0sQzoYm
nED7W+kHch5bbO8wGGt3UyX39aY9yzpe63/R/LpdaOuKVqUEhC+/kthgaGAZd5em
K7VYXKL+kwKBgAXi6sbl6ipjmVNrFa/eBFZnHLOKhhU3WiktcsPObnxaHtzWFfYB
RGTJ+J6MAylmfQ62e86uXpS3nReOnSla3ItBqMpz2Fk03DHGy+WnghMp68OdI8mu
2OPcYCOaWQY4dR8Bu59XUGgi9uNLGO13s4zOICYfjnvzi1nB2ehPZLSDAoGACBZE
hoxYpCjr4kmrb4t4eU1OSUy9IIn/HwjQouv6fnNhdn1urwad+/GZp7LEOTTaotSg
MZnqv2GlBoG9zoSqkXlVWmTFjkMStR1qYAsY+XXb2Nuf07JBVajNLk1onsDwTYPx
Nd89cKikYHgWKZkyKqGVncqVIrm365WUWj1il1MCgYA5J/ojhWKVy/oofiKVetRT
qZSGkyO7SKEHrzkWdBt+iOfEfgEmhpgRETOlmSlZgEXylZnTBvcnf1aNi/j0vFPy
nlqJDs/DMg+uR+/h9jfYW3wlY3tvOj77l4en7J++w2tjlUF4CKRW53/CEa0u+pGi
0qcpM7QV+HhjwJ5lS/GKYw==
-----END PRIVATE KEY-----
"""

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
