import XCTest
@testable import Jin

final class MCPTaskWaitTests: XCTestCase {
    func testFirstCompletionReturnsBeforeTimeoutWhenOperationFinishes() async {
        let started = ContinuousClock.now

        await MCPTaskWait.firstCompletion(timeoutNanoseconds: 500_000_000) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let elapsed = started.duration(to: .now)
        XCTAssertLessThan(elapsed, .milliseconds(200))
    }

    func testFirstCompletionDoesNotJoinAStuckOperation() async {
        let started = ContinuousClock.now

        await MCPTaskWait.firstCompletion(timeoutNanoseconds: 50_000_000) {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }

        let elapsed = started.duration(to: .now)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(40))
        XCTAssertLessThan(elapsed, .milliseconds(400))
    }
}
