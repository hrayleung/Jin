import XCTest
@testable import Jin

final class JinActivityKindTests: XCTestCase {
    func testResolveReturnsNilWhenIdle() {
        XCTAssertNil(JinActivitySnapshot().resolved)
    }

    func testResolvePriorityListeningBeatsSearch() {
        let snapshot = JinActivitySnapshot(
            isListening: true,
            hasRunningSearch: true,
            isBusy: true
        )
        XCTAssertEqual(snapshot.resolved, .listening)
    }

    func testResolvePrioritySearchBeatsCodeExecution() {
        let snapshot = JinActivitySnapshot(
            hasRunningSearch: true,
            hasRunningCodeExecution: true,
            isBusy: true
        )
        XCTAssertEqual(snapshot.resolved, .searching)
    }

    func testResolvePriorityCodeExecutionBeatsTools() {
        let snapshot = JinActivitySnapshot(
            hasRunningCodeExecution: true,
            hasRunningTools: true,
            isBusy: true
        )
        XCTAssertEqual(snapshot.resolved, .solving)
    }

    func testResolvePriorityToolsBeatsMedia() {
        let snapshot = JinActivitySnapshot(
            hasRunningTools: true,
            hasGeneratingMedia: true,
            isBusy: true
        )
        XCTAssertEqual(snapshot.resolved, .connecting)
    }

    func testResolvePriorityMediaBeatsVisibleText() {
        let snapshot = JinActivitySnapshot(
            hasGeneratingMedia: true,
            hasVisibleText: true,
            isBusy: true
        )
        XCTAssertEqual(snapshot.resolved, .shaping)
    }

    func testResolvePriorityVisibleTextBeatsThinking() {
        let snapshot = JinActivitySnapshot(
            hasVisibleText: true,
            isThinking: true,
            isBusy: true
        )
        XCTAssertEqual(snapshot.resolved, .composing)
    }

    func testResolvePriorityThinkingBeatsGenericBusy() {
        let snapshot = JinActivitySnapshot(
            isThinking: true,
            isBusy: true
        )
        XCTAssertEqual(snapshot.resolved, .thinking)
    }

    func testResolveBusyOnlyIsWorking() {
        XCTAssertEqual(JinActivitySnapshot(isBusy: true).resolved, .working)
    }

    func testIsThinkingActiveRequiresIncompleteChunks() {
        XCTAssertTrue(JinActivityKind.isThinkingActive(chunkCount: 2, isComplete: false))
        XCTAssertFalse(JinActivityKind.isThinkingActive(chunkCount: 2, isComplete: true))
        XCTAssertFalse(JinActivityKind.isThinkingActive(chunkCount: 0, isComplete: false))
    }

    func testHasRunningSearchUsesInProgressAndSearching() {
        let running = SearchActivity(id: "1", type: "search", status: .searching)
        let done = SearchActivity(id: "2", type: "search", status: .completed)
        XCTAssertTrue(JinActivityKind.hasRunningSearch([done, running]))
        XCTAssertFalse(JinActivityKind.hasRunningSearch([done]))
    }

    func testHasRunningCodeExecutionUsesActiveStatuses() {
        let running = CodeExecutionActivity(id: "1", status: .writingCode)
        let done = CodeExecutionActivity(id: "2", status: .completed)
        XCTAssertTrue(JinActivityKind.hasRunningCodeExecution([done, running]))
        XCTAssertFalse(JinActivityKind.hasRunningCodeExecution([done]))
    }

    func testResolveStreamingStaysWorkingUntilAMoreSpecificVerbAppears() {
        XCTAssertEqual(
            JinActivityKind.resolveStreaming(
                searchActivities: [],
                codeExecutionActivities: [],
                toolCalls: [],
                toolResultsByCallID: [:],
                artifactCount: 0,
                hasVisibleText: false,
                thinkingChunkCount: 0,
                isThinkingComplete: false
            ),
            .working
        )
    }

    func testResolveStreamingKeepsOneVerbWhenToolsAndTextOverlap() {
        let call = ToolCall(id: "c1", name: "search", arguments: [:])
        XCTAssertEqual(
            JinActivityKind.resolveStreaming(
                searchActivities: [],
                codeExecutionActivities: [],
                toolCalls: [call],
                toolResultsByCallID: [:],
                artifactCount: 0,
                hasVisibleText: true,
                thinkingChunkCount: 2,
                isThinkingComplete: false
            ),
            .connecting
        )
    }

    func testHasRunningToolsWhenResultIsMissing() {
        let call = ToolCall(id: "c1", name: "search", arguments: [:])
        XCTAssertTrue(JinActivityKind.hasRunningTools(toolCalls: [call], resultsByCallID: [:]))
        XCTAssertFalse(
            JinActivityKind.hasRunningTools(
                toolCalls: [call],
                resultsByCallID: ["c1": ToolResult(toolCallID: "c1", content: "ok")]
            )
        )
    }
}
