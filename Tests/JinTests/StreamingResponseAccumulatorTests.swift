import XCTest
@testable import Jin

final class StreamingResponseAccumulatorTests: XCTestCase {
    func testSnapshotBuildsAssistantPartsInStreamOrderAndTagsThinkingProvider() throws {
        var accumulator = StreamingResponseAccumulator(providerType: .anthropic)

        accumulator.appendTextDelta("Hel")
        accumulator.appendTextDelta("lo")
        accumulator.appendThinkingDelta(.thinking(textDelta: "think", signature: "sig_1"))
        accumulator.appendThinkingDelta(.thinking(textDelta: "ing", signature: "sig_1"))
        accumulator.appendThinkingDelta(.redacted(data: "redacted"))

        let snapshot = accumulator.snapshot()

        XCTAssertTrue(snapshot.hasRenderableAssistantContent)
        XCTAssertEqual(snapshot.assistantParts.count, 3)

        guard case .text(let text) = snapshot.assistantParts[0] else {
            return XCTFail("Expected text content part")
        }
        XCTAssertEqual(text, "Hello")

        guard case .thinking(let thinking) = snapshot.assistantParts[1] else {
            return XCTFail("Expected thinking content part")
        }
        XCTAssertEqual(thinking.text, "thinking")
        XCTAssertEqual(thinking.signature, "sig_1")
        XCTAssertEqual(thinking.provider, ProviderType.anthropic.rawValue)

        guard case .redactedThinking(let redacted) = snapshot.assistantParts[2] else {
            return XCTFail("Expected redacted thinking content part")
        }
        XCTAssertEqual(redacted.data, "redacted")
        XCTAssertEqual(redacted.provider, ProviderType.anthropic.rawValue)
    }

    func testSnapshotMergesToolCallsAndKeepsToolOnlyOutputNonRenderable() throws {
        var accumulator = StreamingResponseAccumulator()
        accumulator.upsertToolCall(
            ToolCall(
                id: "call_1",
                name: "",
                arguments: ["query": AnyCodable("swift")],
                signature: "sig_old",
                providerContext: ["thread": "a"]
            )
        )
        accumulator.upsertToolCall(
            ToolCall(
                id: "call_1",
                name: "search",
                arguments: ["limit": AnyCodable(3)],
                signature: nil,
                providerContext: ["turn": "b"]
            )
        )

        let snapshot = accumulator.snapshot()
        let call = try XCTUnwrap(snapshot.toolCalls.first)

        XCTAssertFalse(snapshot.hasRenderableAssistantContent)
        XCTAssertEqual(snapshot.toolCalls.count, 1)
        XCTAssertEqual(call.name, "search")
        XCTAssertEqual(call.arguments["query"]?.value as? String, "swift")
        XCTAssertEqual(call.arguments["limit"]?.value as? Int, 3)
        XCTAssertEqual(call.signature, "sig_old")
        XCTAssertEqual(call.providerContext?["thread"], "a")
        XCTAssertEqual(call.providerContext?["turn"], "b")
    }

    func testSnapshotMarksActivityOnlyOutputRenderable() {
        var accumulator = StreamingResponseAccumulator()
        XCTAssertFalse(accumulator.snapshot().hasRenderableAssistantContent)

        accumulator.upsertSearchActivity(
            SearchActivity(id: "search_1", type: "search", status: .completed)
        )

        let snapshot = accumulator.snapshot()
        XCTAssertTrue(snapshot.hasRenderableAssistantContent)
        XCTAssertEqual(snapshot.searchActivities.count, 1)
    }
}
