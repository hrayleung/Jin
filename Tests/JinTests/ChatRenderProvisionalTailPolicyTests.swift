import XCTest
@testable import Jin

final class ChatRenderProvisionalTailPolicyTests: XCTestCase {

    func testTakesTheTailUpToTheMessageCapInOriginalOrder() throws {
        let snapshots = try (0..<40).map { try makeSnapshot(text: "message \($0)") }
        let slice = ChatRenderProvisionalTailPolicy.tailSlice(of: snapshots)
        XCTAssertEqual(slice.count, ChatRenderProvisionalTailPolicy.maxMessages)
        XCTAssertEqual(slice.map(\.id), snapshots.suffix(24).map(\.id))
    }

    func testStopsAtTheByteBudgetButAlwaysIncludesTheTailMessage() throws {
        // ~100KB each (plus JSON envelope): the budget admits the tail
        // message plus one more before the third crosses 300KB.
        let big = String(repeating: "x", count: 100_000)
        let snapshots = try (0..<5).map { _ in try makeSnapshot(text: big) }
        let slice = ChatRenderProvisionalTailPolicy.tailSlice(of: snapshots)
        XCTAssertEqual(slice.count, 2)
        XCTAssertEqual(slice.last?.id, snapshots.last?.id)

        // A tail message alone over the total budget still paints.
        let oversizedTail = try [makeSnapshot(text: String(repeating: "y", count: 400_000))]
        XCTAssertEqual(ChatRenderProvisionalTailPolicy.tailSlice(of: oversizedTail).count, 1)
    }

    func testGivesUpWhenTheTailMessageExceedsTheSingleMessageCeiling() throws {
        let huge = try makeSnapshot(text: String(repeating: "z", count: 2_100_000))
        let snapshots = try [makeSnapshot(text: "small"), huge]
        XCTAssertTrue(ChatRenderProvisionalTailPolicy.tailSlice(of: snapshots).isEmpty)
    }

    func testStopsWalkingAtAnInteriorHugeMessage() throws {
        let snapshots = try [
            makeSnapshot(text: "old"),
            makeSnapshot(text: String(repeating: "z", count: 2_100_000)),
            makeSnapshot(text: "newest"),
        ]
        let slice = ChatRenderProvisionalTailPolicy.tailSlice(of: snapshots)
        XCTAssertEqual(slice.map(\.id), [snapshots[2].id], "the walk must not leap over an undecodable-budget message")
    }

    func testEmptyInputYieldsEmptySlice() {
        XCTAssertTrue(ChatRenderProvisionalTailPolicy.tailSlice(of: []).isEmpty)
    }

    private func makeSnapshot(text: String) throws -> PersistedMessageSnapshot {
        PersistedMessageSnapshot(
            try MessageEntity.fromDomain(
                Message(id: UUID(), role: .user, content: [.text(text)], timestamp: Date())
            )
        )
    }
}
