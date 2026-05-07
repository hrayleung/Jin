import XCTest
@testable import Jin

@MainActor
final class StreamingMessageStateThroughputTests: XCTestCase {
    func testAppendDeltasStaysFastForLongStream() {
        let state = StreamingMessageState()
        let chunkCount = 50
        let chunkSize = 100
        let chunk = String(repeating: "x", count: chunkSize)

        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<chunkCount {
            state.appendDeltas(textDelta: chunk, thinkingDelta: "")
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        XCTAssertEqual(state.textContent.count, chunkCount * chunkSize)
        // Sanity guard against the O(N²) regression that motivated this branch.
        // 50 chunks of 100 chars in a debug build should comfortably finish in
        // well under a second; the threshold is generous to avoid flake on CI.
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
