import XCTest
@testable import Jin

/// Verifies the shared plugin debounce-autosave helper preserves the exact
/// semantics the views relied on inline: the persist closure runs (on the main
/// actor) after the delay, and a cancelled task never runs it.
final class PluginAutosaveTests: XCTestCase {
    func testRunsPersistAfterDelay() async {
        let ran = expectation(description: "persist ran")
        _ = PluginAutosave.schedule(delayNanos: 30_000_000) {
            XCTAssertTrue(Thread.isMainThread, "persist must run on the main actor")
            ran.fulfill()
        }
        await fulfillment(of: [ran], timeout: 2)
    }

    func testCancelBeforeDelaySkipsPersist() async {
        let didRun = Box(false)
        let task = PluginAutosave.schedule(delayNanos: 300_000_000) { didRun.value = true }
        task.cancel()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let ran = await MainActor.run { didRun.value }
        XCTAssertFalse(ran, "cancelled autosave must not persist")
    }

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }
}
