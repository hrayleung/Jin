import XCTest
@testable import Jin

final class StreamingMessageStateTests: XCTestCase {
    func testAppendDeltasIncrementsRenderTickOnce() {
        let state = StreamingMessageState()

        state.appendDeltas(textDelta: "hello", thinkingDelta: "world")

        XCTAssertEqual(state.renderTick, 1)
        XCTAssertEqual(state.textContent, "hello")
        XCTAssertEqual(state.thinkingContent, "world")
    }

    func testAppendDeltasTracksVisibleText() {
        let state = StreamingMessageState()

        state.appendDeltas(textDelta: "   \n\t", thinkingDelta: "")
        XCTAssertFalse(state.hasVisibleText)

        state.appendDeltas(textDelta: "a", thinkingDelta: "")
        XCTAssertTrue(state.hasVisibleText)
    }

    func testResetClearsDerivedState() {
        let state = StreamingMessageState()

        state.appendDeltas(textDelta: "hello", thinkingDelta: "reasoning")
        XCTAssertEqual(state.renderTick, 1)
        XCTAssertTrue(state.hasVisibleText)

        state.reset()

        XCTAssertEqual(state.renderTick, 0)
        XCTAssertFalse(state.hasVisibleText)
        XCTAssertEqual(state.textChunks, [])
        XCTAssertEqual(state.thinkingChunks, [])
        XCTAssertEqual(state.textContent, "")
        XCTAssertEqual(state.thinkingContent, "")
    }
}

