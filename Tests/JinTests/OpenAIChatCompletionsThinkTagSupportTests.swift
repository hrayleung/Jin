import XCTest
@testable import Jin

final class OpenAIChatCompletionsThinkTagSupportTests: XCTestCase {
    func testSplitNonStreamingExtractsLeadingThinkBlock() {
        let split = OpenAIChatCompletionsThinkTagSplitter.splitNonStreaming("<think>reason</think>\nAnswer")

        XCTAssertEqual(split.thinking, "reason")
        XCTAssertEqual(split.visible, "\nAnswer")
    }

    func testStreamingProcessHandlesTagsAcrossChunks() {
        var splitter = OpenAIChatCompletionsThinkTagSplitter()

        let first = splitter.process("<think>rea")
        let second = splitter.process("son</think>\nAnswer")
        let remainder = splitter.flushRemainder()

        XCTAssertEqual(first.thinking, "rea")
        XCTAssertEqual(first.visible, "")
        XCTAssertEqual(second.thinking, "son")
        XCTAssertEqual(second.visible, "\nAnswer")
        XCTAssertEqual(remainder.thinking, "")
        XCTAssertEqual(remainder.visible, "")
    }

    func testVisibleTextBeforeTagKeepsTagsVisible() {
        var splitter = OpenAIChatCompletionsThinkTagSplitter()

        let split = splitter.process("Answer <think>not hidden</think>")
        let remainder = splitter.flushRemainder()

        XCTAssertEqual(split.thinking, "")
        XCTAssertEqual(split.visible + remainder.visible, "Answer <think>not hidden</think>")
    }

    func testFlushRemainderPreservesPartialTagAsVisibleText() {
        var splitter = OpenAIChatCompletionsThinkTagSplitter()

        let split = splitter.process("Answer <thi")
        let remainder = splitter.flushRemainder()

        XCTAssertEqual(split.visible + remainder.visible, "Answer <thi")
        XCTAssertEqual(split.thinking + remainder.thinking, "")
    }
}
