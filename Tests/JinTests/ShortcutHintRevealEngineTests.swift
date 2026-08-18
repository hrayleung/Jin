import XCTest
@testable import Jin

final class ShortcutHintRevealEngineTests: XCTestCase {
    private let holdDelay: TimeInterval = 0.2

    private func input(
        _ modifiers: AppShortcutModifiers,
        at timestamp: TimeInterval,
        focus: ShortcutHintFocus = .unknown,
        isEnabled: Bool = true,
        isCaptureActive: Bool = false
    ) -> ShortcutHintRevealInput {
        ShortcutHintRevealInput(
            modifiers: modifiers,
            focus: focus,
            isEnabled: isEnabled,
            isCaptureActive: isCaptureActive,
            timestamp: timestamp
        )
    }

    private func resolve(
        _ state: ShortcutHintRevealState,
        _ input: ShortcutHintRevealInput
    ) -> ShortcutHintRevealState {
        ShortcutHintRevealEngine.resolve(state: state, input: input, holdDelay: holdDelay)
    }

    func testCommandHeldShorterThanDelayDoesNotReveal() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10))
        state = resolve(state, input([.command], at: 10.1))

        XCTAssertFalse(state.isRevealed)
        XCTAssertEqual(state.heldModifiers, [.command])
    }

    func testCommandHeldPastDelayReveals() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10))
        state = resolve(state, input([.command], at: 10.3))

        XCTAssertTrue(state.isRevealed)
    }

    /// The whole point of sampling: a single tick that arrives long after ⌘
    /// went down still reveals, so a swallowed `flagsChanged` costs nothing.
    func testRevealDoesNotDependOnReceivingEveryTick() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10))
        state = resolve(state, input([.command], at: 25))

        XCTAssertTrue(state.isRevealed)
    }

    func testReleasingCommandHidesAndClearsHoldClock() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10))
        state = resolve(state, input([.command], at: 10.5))
        state = resolve(state, input([], at: 11))

        XCTAssertFalse(state.isRevealed)
        XCTAssertNil(state.commandDownAt)
        XCTAssertEqual(state.heldModifiers, [])
    }

    func testChordHidesBadgesAndBlocksRerevealWhileCommandStaysDown() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10))
        state = resolve(state, input([.command], at: 10.5))
        XCTAssertTrue(state.isRevealed)

        ShortcutHintRevealEngine.markChord(state: &state, eventModifiers: [.command])
        XCTAssertFalse(state.isRevealed)

        state = resolve(state, input([.command], at: 12))
        XCTAssertFalse(state.isRevealed)
    }

    func testReleasingCommandClearsChordSoTheNextHoldWorks() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10))
        ShortcutHintRevealEngine.markChord(state: &state, eventModifiers: [.command])
        state = resolve(state, input([], at: 11))

        XCTAssertFalse(state.isChordInProgress)

        state = resolve(state, input([.command], at: 12))
        state = resolve(state, input([.command], at: 12.5))
        XCTAssertTrue(state.isRevealed)
    }

    func testOrdinaryTypingDoesNotPoisonTheNextHold() {
        var state = ShortcutHintRevealState()
        ShortcutHintRevealEngine.markChord(state: &state, eventModifiers: [])
        XCTAssertFalse(state.isChordInProgress)

        state = resolve(state, input([.command], at: 10))
        state = resolve(state, input([.command], at: 10.5))
        XCTAssertTrue(state.isRevealed)
    }

    func testAddingShiftWhileRevealedKeepsRevealAndUpdatesModifiers() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10))
        state = resolve(state, input([.command], at: 10.5))
        state = resolve(state, input([.command, .shift], at: 10.6))

        XCTAssertTrue(state.isRevealed)
        XCTAssertEqual(state.heldModifiers, [.command, .shift])
    }

    func testDisabledPreferencePreventsReveal() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10, isEnabled: false))
        state = resolve(state, input([.command], at: 10.5, isEnabled: false))

        XCTAssertFalse(state.isRevealed)
    }

    func testCaptureSessionPreventsReveal() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10, isCaptureActive: true))
        state = resolve(state, input([.command], at: 10.5, isCaptureActive: true))

        XCTAssertFalse(state.isRevealed)
    }

    func testForeignFocusPreventsReveal() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10, focus: .foreign))
        state = resolve(state, input([.command], at: 10.5, focus: .foreign))

        XCTAssertFalse(state.isRevealed)
        XCTAssertNil(state.restrictedWindowID)
    }

    /// Unresolvable focus must fail open: an app-wide blackout is a worse
    /// failure than a badge on a window that just lost focus.
    func testUnknownFocusStillReveals() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10, focus: .unknown))
        state = resolve(state, input([.command], at: 10.5, focus: .unknown))

        XCTAssertTrue(state.isRevealed)
        XCTAssertNil(state.restrictedWindowID)
    }

    /// Regression: the toolbar lives in its own `NSWindow` in full screen, so
    /// ordinary focus must publish no window restriction at all. Restricting to
    /// the focused window silently hid every toolbar badge for a whole session.
    func testOrdinaryFocusRestrictsNoWindow() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10, focus: .host))
        state = resolve(state, input([.command], at: 10.5, focus: .host))

        XCTAssertTrue(state.isRevealed)
        XCTAssertNil(state.restrictedWindowID)
    }

    func testSheetFocusRestrictsHintsToTheSheet() {
        let marker = NSObject()
        let identifier = ObjectIdentifier(marker)
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10, focus: .sheet(identifier)))
        state = resolve(state, input([.command], at: 10.5, focus: .sheet(identifier)))

        XCTAssertTrue(state.isRevealed)
        XCTAssertEqual(state.restrictedWindowID, identifier)
    }

    func testRegainingFocusRestartsTheHoldInsteadOfRevealingInstantly() {
        var state = ShortcutHintRevealState()
        state = resolve(state, input([.command], at: 10))
        state = resolve(state, input([.command], at: 10.5))
        XCTAssertTrue(state.isRevealed)

        ShortcutHintRevealEngine.restartHold(state: &state)
        XCTAssertFalse(state.isRevealed)

        state = resolve(state, input([.command], at: 10.6))
        XCTAssertFalse(state.isRevealed)

        state = resolve(state, input([.command], at: 10.85))
        XCTAssertTrue(state.isRevealed)
    }
}
