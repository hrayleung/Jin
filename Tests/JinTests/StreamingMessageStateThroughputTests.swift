import XCTest
@testable import Jin

@MainActor
final class StreamingMessageStateThroughputTests: XCTestCase {
    func testAppendDeltasStaysFastForLongStream() {
        let state = StreamingMessageState()
        let chunkCount = 200
        let chunkSize = 500
        let chunk = String(repeating: "x", count: chunkSize)

        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<chunkCount {
            state.appendDeltas(textDelta: chunk, thinkingDelta: "")
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        XCTAssertEqual(state.textContent.count, chunkCount * chunkSize)
        XCTAssertGreaterThan(state.visibleTextChunks.count, 1)
        XCTAssertLessThanOrEqual(state.visibleTextChunks.map(\.count).max() ?? 0, 2_048)
        // Sanity guard against the O(N²) regression that motivated this branch.
        // 100k streamed chars in a debug build should comfortably finish in
        // under a second when the hot path avoids full-string trimming/copying.
        XCTAssertLessThan(elapsed, 1.0, "appendDeltas threw away its incremental scan budget (took \(elapsed)s)")
    }

    func testAppendDeltasOnArtifactStreamRemainsFast() {
        let state = StreamingMessageState()
        let prefix = "intro text "
        let artifactOpen = "<jinArtifact artifact_id=\"x\" title=\"X\" contentType=\"text/html\">"
        let artifactBody = String(repeating: "<div>row</div>", count: 200)
        let artifactClose = "</jinArtifact>"
        let suffix = String(repeating: " trailing words ", count: 200)

        let pieces = [prefix, artifactOpen, artifactBody, artifactClose, suffix]
        let started = ProcessInfo.processInfo.systemUptime
        for piece in pieces {
            // Stream each piece in 50-char chunks, simulating per-flush deltas.
            let nsPiece = piece as NSString
            var offset = 0
            while offset < nsPiece.length {
                let next = min(50, nsPiece.length - offset)
                state.appendDeltas(
                    textDelta: nsPiece.substring(with: NSRange(location: offset, length: next)),
                    thinkingDelta: ""
                )
                offset += next
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        XCTAssertEqual(state.artifacts.count, 1)
        XCTAssertLessThan(elapsed, 1.0, "artifact-bearing stream blew the budget at \(elapsed)s")
    }
}
