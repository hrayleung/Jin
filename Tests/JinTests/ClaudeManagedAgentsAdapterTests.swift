import XCTest
@testable import Jin

final class ClaudeManagedAgentsAdapterTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ClaudeManagedAgentsMockURLProtocol.requestHandler = nil
    }

    func testManagedAgentStreamingAggregatesUsageAndExtractsNestedSearchSources() async throws {
        let (configuration, protocolType) = makeClaudeManagedAgentsMockedSessionConfiguration()
        let networkManager = NetworkManager(configuration: configuration)

        let providerConfig = ProviderConfig(
            id: "claude-managed",
            name: "Claude Managed Agents",
            type: .claudeManagedAgents,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )

        protocolType.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            switch (request.httpMethod, url.path) {
            case ("POST", "/v1/sessions"):
                let payload = try JSONSerialization.data(withJSONObject: [
                    "id": "sess_123"
                ])
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    payload
                )

            case ("POST", "/v1/sessions/sess_123/events"):
                let payload = try JSONSerialization.data(withJSONObject: [
                    "ok": true
                ])
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    payload
                )

            case ("GET", "/v1/sessions/sess_123/events/stream"):
                let sse = """
                data: {"type":"session.status_running"}

                data: {"type":"agent.tool_use","id":"sevt_search_1","name":"web_search","input":{"query":"swift 6.2 release notes"},"evaluated_permission":"allow"}

                data: {"type":"span.model_request_end","model_usage":{"input_tokens":3,"output_tokens":5,"cache_read_input_tokens":7,"cache_creation_input_tokens":11}}

                data: {"type":"agent.tool_result","tool_use_id":"sevt_search_1","is_error":false,"content":[{"type":"web_search_result","source":{"url":"https://example.com/swift-6-2","title":"Swift 6.2 Release Notes"},"snippet":"Actor isolation diagnostics improved."},{"type":"web_search_result","source":{"url":"https://swift.org/blog/swift-6-2","title":"Swift.org Blog"},"text":"Swift 6.2 announcement."}]}

                data: {"type":"agent.message","id":"msg_1","content":[{"type":"text","text":"Swift 6.2 is available now.","citations":[{"type":"web_search_result_location","url":"https://example.com/swift-6-2","title":"Swift 6.2 Release Notes","cited_text":"Actor isolation diagnostics improved."}]}]}

                data: {"type":"span.model_request_end","model_usage":{"input_tokens":13,"output_tokens":17,"cache_read_input_tokens":19,"cache_creation_input_tokens":23}}

                data: {"type":"session.status_idle","stop_reason":{"type":"end_turn"}}

                data: [DONE]

                """

                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!,
                    Data(sse.utf8)
                )

            default:
                throw URLError(.badServerResponse)
            }
        }

        let adapter = ClaudeManagedAgentsAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: networkManager
        )

        var controls = GenerationControls()
        controls.claudeManagedAgentID = "agent_123"
        controls.claudeManagedEnvironmentID = "env_456"

        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("What is new in Swift 6.2?")])],
            modelID: "claude-sonnet-4-6",
            controls: controls,
            tools: [],
            streaming: true
        )

        var searchActivities: [SearchActivity] = []
        var textDeltas: [String] = []
        var finalUsage: Usage?

        for try await event in stream {
            switch event {
            case .searchActivity(let activity):
                searchActivities.append(activity)
            case .contentDelta(.text(let text)):
                textDeltas.append(text)
            case .messageEnd(let usage):
                finalUsage = usage
            default:
                break
            }
        }

        XCTAssertEqual(textDeltas, ["Swift 6.2 is available now."])

        let completedSearch = try XCTUnwrap(
            searchActivities.last(where: { $0.id == "sevt_search_1" && $0.status == .completed })
        )
        XCTAssertEqual(completedSearch.arguments["query"]?.value as? String, "swift 6.2 release notes")

        let sources = try XCTUnwrap(completedSearch.arguments["sources"]?.value as? [[String: Any]])
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources.first?["url"] as? String, "https://example.com/swift-6-2")
        XCTAssertEqual(sources.first?["title"] as? String, "Swift 6.2 Release Notes")

        let citationActivity = try XCTUnwrap(
            searchActivities.last(where: { $0.id == "msg_1:sources" && $0.status == .completed })
        )
        XCTAssertEqual(citationActivity.arguments["url"]?.value as? String, "https://example.com/swift-6-2")

        XCTAssertEqual(finalUsage?.inputTokens, 16)
        XCTAssertEqual(finalUsage?.outputTokens, 22)
        XCTAssertEqual(finalUsage?.cachedTokens, 26)
        XCTAssertEqual(finalUsage?.cacheCreationTokens, 34)
    }
}

private final class ClaudeManagedAgentsMockURLProtocol: URLProtocol {
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

private func makeClaudeManagedAgentsMockedSessionConfiguration() -> (URLSessionConfiguration, ClaudeManagedAgentsMockURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ClaudeManagedAgentsMockURLProtocol.self]
    return (config, ClaudeManagedAgentsMockURLProtocol.self)
}
