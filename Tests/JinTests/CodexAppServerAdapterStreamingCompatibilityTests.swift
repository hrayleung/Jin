import XCTest
@testable import Jin

final class CodexAppServerAdapterStreamingCompatibilityTests: XCTestCase {
    func testParseAgentMessageTextReadsNestedOutputShape() throws {
        let payload: [String: Any] = [
            "type": "agentMessage",
            "message": [
                "content": [
                    [
                        "type": "output_text",
                        "text": "Hello "
                    ],
                    [
                        "type": "output_text",
                        "text": "world"
                    ]
                ]
            ]
        ]

        let item = try TestJSONHelpers.makeJSONObject(payload)
        XCTAssertEqual(CodexAppServerAdapter.parseAgentMessageText(from: item), "Hello world")
    }

    func testAssistantTextSuffixReturnsTailWhenSnapshotExtendsEmittedText() {
        let suffix = CodexAppServerAdapter.assistantTextSuffix(
            fromSnapshot: "Hello world",
            emitted: "Hello "
        )
        XCTAssertEqual(suffix, "world")
    }

    func testAssistantTextSuffixUsesSnapshotWhenOnlyWhitespaceWasStreamed() {
        let suffix = CodexAppServerAdapter.assistantTextSuffix(
            fromSnapshot: "Final answer",
            emitted: "\n\n"
        )
        XCTAssertEqual(suffix, "Final answer")
    }

    func testAssistantTextSuffixIgnoresIncompatibleSnapshotToAvoidDuplicateCorruption() {
        let suffix = CodexAppServerAdapter.assistantTextSuffix(
            fromSnapshot: "Final answer",
            emitted: "Different"
        )
        XCTAssertNil(suffix)
    }

    func testSearchActivityFromDynamicToolCallParsesSearchingStatusAndQuery() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-123",
                "type": "dynamicToolCall",
                "name": "web_search",
                "status": "searching",
                "arguments": [
                    "query": "latest ai server updates"
                ]
            ],
            "turnId": "turn-1"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.searchActivityFromDynamicToolCall(
                item: item,
                method: "item/updated",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.id, "tool-123")
        XCTAssertEqual(activity.type, "web_search_call")
        XCTAssertEqual(activity.status, .searching)
        XCTAssertEqual(activity.arguments["query"]?.value as? String, "latest ai server updates")
    }

    func testSearchActivityFromDynamicToolCallExtractsSourcesFromPayloadAndText() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-456",
                "type": "dynamicToolCall",
                "name": "browser.search",
                "result": [
                    "sources": [
                        [
                            "url": "https://openai.com/blog/example",
                            "title": "Example Blog",
                            "snippet": "Release notes"
                        ]
                    ]
                ],
                "contentItems": [
                    [
                        "type": "inputText",
                        "text": "Also looked at https://platform.openai.com/docs"
                    ]
                ]
            ],
            "turnId": "turn-2"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.searchActivityFromDynamicToolCall(
                item: item,
                method: "item/completed",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.status, .completed)

        guard let sources = activity.arguments["sources"]?.value as? [[String: Any]] else {
            XCTFail("Expected sources")
            return
        }

        let urls = Set(sources.compactMap { $0["url"] as? String })
        XCTAssertTrue(urls.contains("https://openai.com/blog/example"))
        XCTAssertTrue(urls.contains("https://platform.openai.com/docs"))
    }

    func testSearchActivityFromDynamicToolCallSkipsNonSearchTools() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-789",
                "type": "dynamicToolCall",
                "name": "run_command",
                "status": "completed"
            ],
            "turnId": "turn-3"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = CodexAppServerAdapter.searchActivityFromDynamicToolCall(
            item: item,
            method: "item/completed",
            params: params,
            fallbackTurnID: nil
        )

        XCTAssertNil(activity)
    }

    func testSearchActivityFromDynamicToolCallSupportsToolFieldNameAndCamelCaseStatus() throws {
        let payload: [String: Any] = [
            "item": [
                "id": "tool-900",
                "type": "dynamicToolCall",
                "tool": "web_search",
                "status": "inProgress",
                "arguments": [
                    "query": "swift codex app server"
                ]
            ],
            "turnId": "turn-4"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.searchActivityFromDynamicToolCall(
                item: item,
                method: "item/updated",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.status, .inProgress)
        XCTAssertEqual(activity.arguments["query"]?.value as? String, "swift codex app server")
    }

    func testSearchActivityFromDynamicToolCallFallbackIDIncludesSequenceSuffix() throws {
        let payload: [String: Any] = [
            "item": [
                "type": "dynamicToolCall",
                "name": "web_search",
                "sequenceNumber": 3,
                "arguments": [
                    "query": "jin release notes"
                ]
            ],
            "turnId": "turn-seq"
        ]

        let params = try TestJSONHelpers.makeJSONObject(payload)
        let item = try XCTUnwrap(params.object(at: ["item"]))
        let activity = try XCTUnwrap(
            CodexAppServerAdapter.searchActivityFromDynamicToolCall(
                item: item,
                method: "item/updated",
                params: params,
                fallbackTurnID: nil
            )
        )

        XCTAssertEqual(activity.id, "codex_dynamic_search_turn-seq_web_search_seq3")
    }

    func testSearchActivityFromCodexItemParsesWebSearchThreadItemLifecycle() throws {
        let itemPayload: [String: Any] = [
            "id": "ws-1",
            "type": "webSearch",
            "query": "us news",
            "action": [
                "type": "search",
                "queries": ["us news", "us headlines"]
            ]
        ]
        let params = try TestJSONHelpers.makeJSONObject([
            "item": itemPayload,
            "turnId": "turn-5"
        ])
        let item = try XCTUnwrap(params.object(at: ["item"]))

        let started = try XCTUnwrap(
            CodexAppServerAdapter.searchActivityFromCodexItem(
                item: item,
                method: "item/started",
                params: params,
                fallbackTurnID: nil
            )
        )
        XCTAssertEqual(started.id, "ws-1")
        XCTAssertEqual(started.status, .searching)
        XCTAssertEqual(started.arguments["query"]?.value as? String, "us news")

        let completed = try XCTUnwrap(
            CodexAppServerAdapter.searchActivityFromCodexItem(
                item: item,
                method: "item/completed",
                params: params,
                fallbackTurnID: nil
            )
        )
        XCTAssertEqual(completed.id, "ws-1")
        XCTAssertEqual(completed.status, .completed)
    }
}
