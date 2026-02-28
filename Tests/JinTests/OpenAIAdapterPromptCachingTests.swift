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
            XCTAssertNil(root["prompt_cache_min_tokens"])

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
                    "input_tokens_details": [
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

    func testOpenAIAdapterClampsUnsupportedXHighEffortToHigh() async throws {
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

            let body = try XCTUnwrap(openAIRequestBodyData(request))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "high")

            let response: [String: Any] = [
                "id": "resp_high",
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "ok"]
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 1,
                    "output_tokens": 1
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5",
            controls: GenerationControls(reasoning: ReasoningControls(enabled: true, effort: .xhigh)),
            tools: [],
            streaming: false
        )

        for try await _ in stream {}
    }

    func testOpenAIAdapterNonStreamingEmitsWebSearchActivityFromOutputItems() async throws {
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

            let response: [String: Any] = [
                "id": "resp_ws_1",
                "output": [
                    [
                        "id": "ws_1",
                        "type": "web_search_call",
                        "status": "completed",
                        "action": [
                            "type": "search",
                            "query": "swift 6.2 release date"
                        ]
                    ],
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "Answer"]
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 8,
                    "output_tokens": 4
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let searchEvent = try XCTUnwrap(events.compactMap { event -> SearchActivity? in
            if case .searchActivity(let activity) = event { return activity }
            return nil
        }.first)
        XCTAssertEqual(searchEvent.id, "ws_1")
        XCTAssertEqual(searchEvent.type, "search")
        XCTAssertEqual(searchEvent.status, .completed)
        XCTAssertEqual(searchEvent.arguments["query"]?.value as? String, "swift 6.2 release date")
    }

    func testOpenAIAdapterNonStreamingEmitsCitationSearchActivityFromMessageAnnotations() async throws {
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

            let response: [String: Any] = [
                "id": "resp_citation_1",
                "output": [
                    [
                        "id": "msg_1",
                        "type": "message",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "Sources included.",
                                "annotations": [
                                    [
                                        "type": "url_citation",
                                        "url": "https://platform.openai.com/docs/api-reference/responses/create",
                                        "title": "Create response"
                                    ],
                                    [
                                        "type": "url_citation",
                                        "url": "https://www.anthropic.com/news",
                                        "title": "Anthropic News"
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 9,
                    "output_tokens": 6
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        let citation = try XCTUnwrap(searchEvents.first)
        XCTAssertEqual(citation.id, "msg_1:citations")
        XCTAssertEqual(citation.type, "url_citation")
        XCTAssertEqual(citation.status, .completed)

        let sources = citationSources(from: citation)
        XCTAssertEqual(sources.count, 2)
        XCTAssertTrue(sources.contains { $0.url == "https://platform.openai.com/docs/api-reference/responses/create" })
        XCTAssertTrue(sources.contains { $0.url == "https://www.anthropic.com/news" })
    }

    func testOpenAIAdapterStreamingEmitsWebSearchLifecycleEvents() async throws {
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

            let sse = """
            event: response.created
            data: {"type":"response.created","response":{"id":"resp_ws_stream"}}

            event: response.output_item.added
            data: {"type":"response.output_item.added","output_index":0,"sequence_number":1,"item":{"id":"ws_123","type":"web_search_call","status":"in_progress","action":{"type":"search","query":"swift asyncstream"}}}

            event: response.web_search_call.searching
            data: {"type":"response.web_search_call.searching","output_index":0,"item_id":"ws_123","sequence_number":2}

            event: response.web_search_call.completed
            data: {"type":"response.web_search_call.completed","output_index":0,"item_id":"ws_123","sequence_number":3}

            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"Answer"}

            event: response.completed
            data: {"type":"response.completed","response":{"usage":{"input_tokens":3,"output_tokens":2,"output_tokens_details":{"reasoning_tokens":0},"input_tokens_details":{"cached_tokens":0}}}}

            data: [DONE]

            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(sse.utf8)
            )
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        XCTAssertGreaterThanOrEqual(searchEvents.count, 3)
        XCTAssertEqual(searchEvents.first?.id, "ws_123")
        XCTAssertEqual(searchEvents.first?.type, "search")
        XCTAssertEqual(searchEvents.first?.arguments["query"]?.value as? String, "swift asyncstream")
        XCTAssertTrue(searchEvents.contains { $0.status == .searching })
        XCTAssertTrue(searchEvents.contains { $0.status == .completed })
    }

    func testOpenAIAdapterStreamingEmitsCitationSearchActivityFromMessageItemDone() async throws {
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

            let sse = """
            event: response.created
            data: {"type":"response.created","response":{"id":"resp_ws_stream"}}

            event: response.output_item.done
            data: {"type":"response.output_item.done","output_index":1,"sequence_number":4,"item":{"id":"msg_42","type":"message","status":"completed","content":[{"type":"output_text","text":"Answer with source.","annotations":[{"type":"url_citation","url":"https://aistudio.google.com","title":"Google AI Studio"}]}]}}

            event: response.completed
            data: {"type":"response.completed","response":{"usage":{"input_tokens":3,"output_tokens":2}}}

            data: [DONE]

            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(sse.utf8)
            )
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        let citation = try XCTUnwrap(searchEvents.first(where: { $0.id == "msg_42:citations" }))
        let sources = citationSources(from: citation)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.url, "https://aistudio.google.com")
        XCTAssertEqual(sources.first?.title, "Google AI Studio")
    }

    func testOpenAIAdapterStreamingHandlesCompletedEventWithoutUsage() async throws {
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

            let sse = """
            event: response.created
            data: {"type":"response.created","response":{"id":"resp_no_usage_1"}}

            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"ok"}

            event: response.completed
            data: {"type":"response.completed","response":{"id":"resp_no_usage_1"}}

            data: [DONE]

            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(sse.utf8)
            )
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var sawTextDelta = false
        var sawMessageEndWithoutUsage = false
        for try await event in stream {
            switch event {
            case .contentDelta(.text(let text)):
                if text == "ok" {
                    sawTextDelta = true
                }
            case .messageEnd(let usage):
                if usage == nil {
                    sawMessageEndWithoutUsage = true
                }
            default:
                break
            }
        }

        XCTAssertTrue(sawTextDelta)
        XCTAssertTrue(sawMessageEndWithoutUsage)
    }

    func testOpenAIAdapterCitationSearchActivityCarriesSnippetFromAnnotationOffsets() async throws {
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

            let response: [String: Any] = [
                "id": "resp_citation_snippet_1",
                "output": [
                    [
                        "id": "msg_snippet_1",
                        "type": "message",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "Swift 6.2 improves compile-time diagnostics for actor isolation.",
                                "annotations": [
                                    [
                                        "type": "url_citation",
                                        "url": "https://swift.org/blog/",
                                        "title": "Swift Blog",
                                        "start_index": 11,
                                        "end_index": 55
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 8,
                    "output_tokens": 5
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        let citation = try XCTUnwrap(searchEvents.first(where: { $0.id == "msg_snippet_1:citations" }))
        let sources = citationSources(from: citation)
        XCTAssertEqual(sources.first?.url, "https://swift.org/blog/")
        XCTAssertEqual(sources.first?.title, "Swift Blog")
        XCTAssertTrue((sources.first?.snippet ?? "").contains("actor isolation"))
    }

    func testOpenAIAdapterCitationSearchActivityParsesNestedURLCitationWithoutExplicitType() async throws {
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

            let response: [String: Any] = [
                "id": "resp_citation_nested_1",
                "output": [
                    [
                        "id": "msg_nested_1",
                        "type": "message",
                        "content": [
                            [
                                "type": "output_text",
                                "text": "OpenAI released more structured web search source annotations.",
                                "annotations": [
                                    [
                                        "url_citation": [
                                            "url": "https://openai.com/index/introducing-web-search",
                                            "title": "OpenAI Web Search",
                                            "start_index": 0,
                                            "end_index": 45
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 9,
                    "output_tokens": 7
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: false
        )

        var searchEvents: [SearchActivity] = []
        for try await event in stream {
            if case .searchActivity(let activity) = event {
                searchEvents.append(activity)
            }
        }

        let citation = try XCTUnwrap(searchEvents.first(where: { $0.id == "msg_nested_1:citations" }))
        let sources = citationSources(from: citation)
        XCTAssertEqual(sources.first?.url, "https://openai.com/index/introducing-web-search")
        XCTAssertEqual(sources.first?.title, "OpenAI Web Search")
        XCTAssertTrue((sources.first?.snippet ?? "").contains("structured web search"))
    }

    func testOpenAIAdapterStreamingSkipsMalformedEventsInsteadOfFailing() async throws {
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

            let sse = """
            event: response.created
            data: {"type":"response.created","response":{"id":"resp_malformed_1"}}

            event: response.output_item.done
            data: {"type":"response.output_item.done","output_index":0}

            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"ok"}

            event: response.completed
            data: {"type":"response.completed","response":{"id":"resp_malformed_1","usage":{"input_tokens":2,"output_tokens":1}}}

            data: [DONE]

            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(sse.utf8)
            )
        }

        let adapter = OpenAIAdapter(providerConfig: providerConfig, apiKey: "test-key", networkManager: networkManager)
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("hi")])],
            modelID: "gpt-5.2",
            controls: GenerationControls(),
            tools: [],
            streaming: true
        )

        var sawText = false
        var sawMessageEnd = false
        for try await event in stream {
            switch event {
            case .contentDelta(.text(let text)):
                if text == "ok" {
                    sawText = true
                }
            case .messageEnd:
                sawMessageEnd = true
            default:
                break
            }
        }

        XCTAssertTrue(sawText)
        XCTAssertTrue(sawMessageEnd)
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

private func citationSources(from activity: SearchActivity) -> [(url: String, title: String?, snippet: String?)] {
    guard let raw = activity.arguments["sources"]?.value else { return [] }

    let rows: [[String: Any]]
    if let dicts = raw as? [[String: Any]] {
        rows = dicts
    } else if let array = raw as? [Any] {
        rows = array.compactMap { $0 as? [String: Any] }
    } else {
        rows = []
    }

    return rows.compactMap { row in
        guard let url = row["url"] as? String else { return nil }
        return (
            url: url,
            title: row["title"] as? String,
            snippet: row["snippet"] as? String
        )
    }
}
