import XCTest
@testable import Jin

@MainActor
final class StreamingMessageStateThroughputTests: XCTestCase {
    func testAppendDeltasStaysFastForLongStream() {
        let state = StreamingMessageState()
        let chunkCount = 200
        let chunkSize = 500
        let chunk = String(repeating: "x", count: chunkSize)

        for _ in 0..<chunkCount {
            state.appendDeltas(textDelta: chunk, thinkingDelta: "")
        }

        let expectedText = String(repeating: chunk, count: chunkCount)
        XCTAssertEqual(state.textContent, expectedText)
        XCTAssertEqual(state.visibleTextChunks.joined(), expectedText)
        XCTAssertGreaterThan(state.visibleTextChunks.count, 1)
        XCTAssertLessThanOrEqual(state.visibleTextChunks.map(\.count).max() ?? 0, 2_048)
    }

    func testAppendDeltasOnArtifactStreamRemainsFast() {
        let state = StreamingMessageState()
        let prefix = "intro text "
        let artifactOpen = "<jinArtifact artifact_id=\"x\" title=\"X\" contentType=\"text/html\">"
        let artifactBody = String(repeating: "<div>row</div>", count: 200)
        let artifactClose = "</jinArtifact>"
        let suffix = String(repeating: " trailing words ", count: 200)

        let pieces = [prefix, artifactOpen, artifactBody, artifactClose, suffix]
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

        XCTAssertEqual(state.artifacts.count, 1)
        XCTAssertEqual(state.artifacts.first?.artifactID, "x")
        XCTAssertEqual(state.artifacts.first?.title, "X")
        XCTAssertEqual(state.artifacts.first?.contentType, .html)
        XCTAssertEqual(state.artifacts.first?.content, artifactBody)
        XCTAssertEqual(state.visibleText, prefix + suffix)
    }
}
