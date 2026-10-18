import XCTest
@testable import Jin

/// A long server-tool turn (web search at max effort) ends its first response with
/// `stop_reason: "pause_turn"` and a trailing `server_tool_use` that has no result yet. Jin used to
/// treat that as a finished reply, so the bubble stopped after the thinking block with no answer.
final class AnthropicPauseTurnContinuationTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Recorder

    func testRecorderRebuildsPausedResponseContentAsIs() throws {
        var recorder = AnthropicStreamedResponseRecorder()
        for line in pausedResponseLines(containerID: "container_1") {
            recorder.record(line)
        }

        XCTAssertEqual(recorder.stopReason, "pause_turn")
        XCTAssertEqual(recorder.containerID, "container_1")
        XCTAssertEqual(try canonicalJSON(recorder.content), try canonicalJSON(expectedPausedContent))
    }

    func testRecorderAppendsCitationsDeltasToTextBlock() throws {
        var recorder = AnthropicStreamedResponseRecorder()
        let lines = [
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Deadline is "}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://www.universityadmissions.se","title":"UHR","encrypted_index":"idx-1","cited_text":"15 January"}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"15 January."}}"#,
            #"{"type":"content_block_stop","index":0}"#
        ]
        for line in lines {
            recorder.record(line)
        }

        let expected: [[String: Any]] = [[
            "type": "text",
            "text": "Deadline is 15 January.",
            "citations": [[
                "type": "web_search_result_location",
                "url": "https://www.universityadmissions.se",
                "title": "UHR",
                "encrypted_index": "idx-1",
                "cited_text": "15 January"
            ]]
        ]]
        XCTAssertEqual(try canonicalJSON(recorder.content), try canonicalJSON(expected))
    }

    // MARK: - Continuation

    func testPausedTurnIsResumedWithPausedContentAndSameTools() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyJSON(request))
            let index = recorder.append(body)
            let lines = index == 0
                ? pausedResponseLines(containerID: "container_1")
                : resumedResponseLines()
            return (okResponse(for: request), sse(lines))
        }

        let events = try await collectEvents(from: makeAdapter())

        let bodies = recorder.bodies
        XCTAssertEqual(bodies.count, 2)
        let first = try XCTUnwrap(bodies.first)
        let second = try XCTUnwrap(bodies.last)

        // The resume is the original request plus the paused response, unchanged.
        let firstMessages = try XCTUnwrap(first["messages"] as? [[String: Any]])
        let secondMessages = try XCTUnwrap(second["messages"] as? [[String: Any]])
        XCTAssertEqual(secondMessages.count, firstMessages.count + 1)
        XCTAssertEqual(try canonicalJSON(Array(secondMessages.prefix(firstMessages.count))), try canonicalJSON(firstMessages))
        let resumedAssistant = try XCTUnwrap(secondMessages.last)
        XCTAssertEqual(resumedAssistant["role"] as? String, "assistant")
        let resumedContent = try XCTUnwrap(resumedAssistant["content"] as? [[String: Any]])
        XCTAssertEqual(try canonicalJSON(resumedContent), try canonicalJSON(expectedPausedContent))
        // Same tools (the API 400s if the pending server tool disappears), same limits, and the
        // code execution container the paused response ran in.
        let firstTools = try XCTUnwrap(first["tools"] as? [[String: Any]])
        let secondTools = try XCTUnwrap(second["tools"] as? [[String: Any]])
        XCTAssertEqual(firstTools.first?["name"] as? String, "web_search")
        XCTAssertEqual(try canonicalJSON(secondTools), try canonicalJSON(firstTools))
        XCTAssertEqual(second["max_tokens"] as? Int, first["max_tokens"] as? Int)
        XCTAssertNil(first["container"])
        XCTAssertEqual(second["container"] as? String, "container_1")

        // The reply keeps streaming into one message: no end before the resumed answer.
        let finalTextIndex = try XCTUnwrap(events.lastIndex { event in
            if case .contentDelta(.text(let text)) = event { return text == "Here is the plan." }
            return false
        })
        let firstEndIndex = try XCTUnwrap(events.firstIndex { event in
            if case .messageEnd = event { return true }
            return false
        })
        XCTAssertGreaterThan(firstEndIndex, finalTextIndex)
        XCTAssertFalse(events.contains { event in
            if case .contentDelta(.text(let text)) = event { return text.contains("Response stopped early") }
            return false
        })

        // Usage covers both requests of the turn.
        guard case .messageEnd(let usage?) = events[firstEndIndex] else {
            return XCTFail("Expected usage on messageEnd")
        }
        XCTAssertEqual(usage.inputTokens, 150)
        XCTAssertEqual(usage.outputTokens, 650)
        XCTAssertEqual(usage.cachedTokens, 7000)
        XCTAssertEqual(usage.cacheCreationTokens, 300)

        // The pending search's result arrives in the resumed response and completes the same
        // activity, ordered after every block of the paused response.
        let pendingSearchUpdates = events.compactMap { event -> SearchActivity? in
            guard case .searchActivity(let activity) = event, activity.id == "srvtoolu_2" else { return nil }
            return activity
        }
        let completed = try XCTUnwrap(pendingSearchUpdates.last)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertNotNil(completed.arguments["sources"])
        XCTAssertEqual(completed.sequenceNumber, expectedPausedContent.count)
    }

    func testPauseTurnStopsResumingAtCapAndExplainsWhy() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyJSON(request))
            _ = recorder.append(body)
            return (okResponse(for: request), sse(pausedResponseLines(containerID: nil)))
        }

        let events = try await collectEvents(from: makeAdapter())

        XCTAssertEqual(recorder.bodies.count, AnthropicStopReasonSupport.maxPauseTurnContinuations + 1)
        let notice = try XCTUnwrap(events.compactMap { event -> String? in
            guard case .contentDelta(.text(let text)) = event, text.contains("Response stopped early") else { return nil }
            return text
        }.first)
        XCTAssertTrue(notice.contains("\(AnthropicStopReasonSupport.maxPauseTurnContinuations) automatic continuations"))
        guard case .messageEnd = events.last else {
            return XCTFail("Expected the reply to end after the notice, got \(String(describing: events.last))")
        }
        // Every resume carries all paused segments so far, in order.
        let lastMessages = try XCTUnwrap(recorder.bodies.last?["messages"] as? [[String: Any]])
        let lastAssistantContent = try XCTUnwrap(lastMessages.last?["content"] as? [Any])
        XCTAssertEqual(
            lastAssistantContent.count,
            expectedPausedContent.count * AnthropicStopReasonSupport.maxPauseTurnContinuations
        )
    }

    func testMaxTokensCutoffAppendsNoticeInsteadOfEndingSilently() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyJSON(request))
            _ = recorder.append(body)
            let lines = [
                #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}"#,
                #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
                #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Still reasoning"}}"#,
                #"{"type":"message_delta","delta":{"stop_reason":"max_tokens","stop_sequence":null},"usage":{"output_tokens":64000}}"#,
                #"{"type":"message_stop"}"#
            ]
            return (okResponse(for: request), sse(lines))
        }

        let events = try await collectEvents(from: makeAdapter())

        XCTAssertEqual(recorder.bodies.count, 1)
        let noticeIndex = try XCTUnwrap(events.firstIndex { event in
            if case .contentDelta(.text(let text)) = event { return text.contains("max output token limit") }
            return false
        })
        let endIndex = try XCTUnwrap(events.firstIndex { event in
            if case .messageEnd = event { return true }
            return false
        })
        XCTAssertLessThan(noticeIndex, endIndex)
    }

    func testMidStreamErrorEventSurfacesInsteadOfEndingSilently() async throws {
        MockURLProtocol.requestHandler = { request in
            let lines = [
                #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}"#,
                #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
                #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Working"}}"#,
                #"{"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}"#
            ]
            return (okResponse(for: request), sse(lines))
        }

        let events = try await collectEvents(from: makeAdapter())

        let error = try XCTUnwrap(events.compactMap { event -> LLMError? in
            guard case .error(let error) = event else { return nil }
            return error
        }.first)
        guard case .providerError(let code, let message) = error else {
            return XCTFail("Expected providerError, got \(error)")
        }
        XCTAssertEqual(code, "overloaded_error")
        XCTAssertEqual(message, "Overloaded")
    }

    func testEndTurnStillEndsWithoutNoticeOrSecondRequest() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            let body = try XCTUnwrap(requestBodyJSON(request))
            _ = recorder.append(body)
            let lines = [
                #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}"#,
                #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
                #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done."}}"#,
                #"{"type":"content_block_stop","index":0}"#,
                #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":3}}"#,
                #"{"type":"message_stop"}"#
            ]
            return (okResponse(for: request), sse(lines))
        }

        let events = try await collectEvents(from: makeAdapter())

        XCTAssertEqual(recorder.bodies.count, 1)
        let texts = events.compactMap { event -> String? in
            guard case .contentDelta(.text(let text)) = event else { return nil }
            return text
        }
        XCTAssertEqual(texts, ["Done."])
        XCTAssertTrue(events.contains { event in
            if case .messageEnd = event { return true }
            return false
        })
    }

    // MARK: - Helpers

    private func makeAdapter() -> AnthropicAdapter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let providerConfig = ProviderConfig(
            id: "anthropic",
            name: "Anthropic",
            type: .anthropic,
            apiKey: "ignored",
            baseURL: "https://example.com"
        )
        return AnthropicAdapter(
            providerConfig: providerConfig,
            apiKey: "test-key",
            networkManager: NetworkManager(configuration: configuration)
        )
    }

    private func collectEvents(from adapter: AnthropicAdapter) async throws -> [StreamEvent] {
        let stream = try await adapter.sendMessage(
            messages: [Message(role: .user, content: [.text("Plan my Sweden master's applications.")])],
            modelID: "claude-opus-5-5",
            controls: GenerationControls(
                maxTokens: 64000,
                reasoning: ReasoningControls(enabled: true, effort: .max),
                webSearch: WebSearchControls(enabled: true)
            ),
            tools: [],
            streaming: true
        )
        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

// MARK: - Fixtures

/// thinking → search (with result) → text → thinking → search still pending, then `pause_turn`.
private func pausedResponseLines(containerID: String?) -> [String] {
    let container = containerID.map { #","container":{"id":"\#($0)","expires_at":"2026-10-18T14:00:00Z"}"# } ?? ""
    return [
        #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":1}}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Check the application round first."}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig-1"}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{}}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"universityadmissions"}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" autumn 2027\"}"}}"#,
        #"{"type":"content_block_stop","index":1}"#,
        #"{"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","title":"Application dates","url":"https://www.universityadmissions.se/dates","encrypted_content":"enc-1","page_age":null}]}}"#,
        #"{"type":"content_block_stop","index":2}"#,
        #"{"type":"content_block_start","index":3,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"Checking programmes."}}"#,
        #"{"type":"content_block_stop","index":3}"#,
        #"{"type":"content_block_start","index":4,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
        #"{"type":"content_block_delta","index":4,"delta":{"type":"thinking_delta","thinking":"Now KTH requirements."}}"#,
        #"{"type":"content_block_delta","index":4,"delta":{"type":"signature_delta","signature":"sig-2"}}"#,
        #"{"type":"content_block_stop","index":4}"#,
        #"{"type":"content_block_start","index":5,"content_block":{"type":"server_tool_use","id":"srvtoolu_2","name":"web_search","input":{}}}"#,
        #"{"type":"content_block_delta","index":5,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"KTH entry requirements\"}"}}"#,
        #"{"type":"content_block_stop","index":5}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"pause_turn","stop_sequence":null\#(container)},"usage":{"input_tokens":100,"cache_read_input_tokens":5000,"cache_creation_input_tokens":300,"output_tokens":400}}"#,
        #"{"type":"message_stop"}"#
    ]
}

private let expectedPausedContent: [[String: Any]] = [
    ["type": "thinking", "thinking": "Check the application round first.", "signature": "sig-1"],
    ["type": "server_tool_use", "id": "srvtoolu_1", "name": "web_search", "input": ["query": "universityadmissions autumn 2027"]],
    [
        "type": "web_search_tool_result",
        "tool_use_id": "srvtoolu_1",
        "content": [[
            "type": "web_search_result",
            "title": "Application dates",
            "url": "https://www.universityadmissions.se/dates",
            "encrypted_content": "enc-1",
            "page_age": NSNull()
        ]]
    ],
    ["type": "text", "text": "Checking programmes."],
    ["type": "thinking", "thinking": "Now KTH requirements.", "signature": "sig-2"],
    ["type": "server_tool_use", "id": "srvtoolu_2", "name": "web_search", "input": ["query": "KTH entry requirements"]]
]

/// The resumed response starts with the result for the pending `srvtoolu_2`.
private func resumedResponseLines() -> [String] {
    [
        #"{"type":"message_start","message":{"id":"msg_2","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":50,"cache_read_input_tokens":2000,"output_tokens":1}}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_2","content":[{"type":"web_search_result","title":"KTH entry requirements","url":"https://www.kth.se/en/studies/master","encrypted_content":"enc-2","page_age":null}]}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"content_block_start","index":1,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"thinking_delta","thinking":"Enough to answer."}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"signature_delta","signature":"sig-3"}}"#,
        #"{"type":"content_block_stop","index":1}"#,
        #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
        #"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Here is the plan."}}"#,
        #"{"type":"content_block_stop","index":2}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":50,"cache_read_input_tokens":2000,"cache_creation_input_tokens":0,"output_tokens":250}}"#,
        #"{"type":"message_stop"}"#
    ]
}

private func sse(_ lines: [String]) -> Data {
    let body = lines.map { line -> String in
        let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        let type = object?["type"] as? String ?? "message"
        return "event: \(type)\ndata: \(line)\n\n"
    }.joined()
    return Data(body.utf8)
}

private func okResponse(for request: URLRequest) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
}

private func canonicalJSON(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func requestBodyJSON(_ request: URLRequest) -> [String: Any]? {
    let data: Data?
    if let body = request.httpBody {
        data = body
    } else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            collected.append(buffer, count: read)
        }
        data = collected
    } else {
        data = nil
    }
    guard let data else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[String: Any]] = []

    /// Returns the zero-based index of the recorded request.
    func append(_ body: [String: Any]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage.append(body)
        return storage.count - 1
    }

    var bodies: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
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
