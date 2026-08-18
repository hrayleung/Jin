import AppKit
import XCTest
@testable import Jin

final class ShortcutHintModifierFlagsSupportTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
    }

    func testLogicalModifiersMapCommandFromNSEventFlags() {
        XCTAssertEqual(
            AppShortcutModifiers(eventFlags: .command),
            [.command]
        )
        XCTAssertEqual(
            AppShortcutModifiers(eventFlags: [.command, .shift]),
            [.command, .shift]
        )
    }

    func testModifierKeyCodesIncludeBothCommandKeys() {
        XCTAssertTrue(ShortcutHintModifierFlagsSupport.isModifierKeyCode(54))
        XCTAssertTrue(ShortcutHintModifierFlagsSupport.isModifierKeyCode(55))
        XCTAssertTrue(ShortcutHintModifierFlagsSupport.isModifierKeyCode(57))
        XCTAssertFalse(ShortcutHintModifierFlagsSupport.isModifierKeyCode(0))
    }

    func testFocusIsForeignWhenAnotherAppIsActive() {
        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [makeWindow()],
                isAppActive: false,
                keyWindow: nil,
                mainWindow: nil,
                lastKeyWindow: nil
            ),
            .foreign
        )
    }

    /// Before any window registers there is nothing to compare against, so the
    /// answer is "unknown" — never a silent "no".
    func testFocusIsUnknownWithoutRegisteredWindows() {
        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [],
                isAppActive: true,
                keyWindow: nil,
                mainWindow: nil,
                lastKeyWindow: nil
            ),
            .unknown
        )
    }

    func testFocusResolvesKeyHostWindow() {
        let host = makeWindow()

        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [host],
                isAppActive: true,
                keyWindow: host,
                mainWindow: host,
                lastKeyWindow: nil
            ),
            .host
        )
    }

    /// Regression: full screen hosts the toolbar in its own parentless
    /// `NSToolbarFullScreenWindow`. Registering it as a host is what stops
    /// every toolbar badge from being suppressed for the whole session.
    func testFocusTreatsARegisteredChromeWindowAsHost() {
        let main = makeWindow()
        let toolbar = makeWindow()

        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [main, toolbar],
                isAppActive: true,
                keyWindow: toolbar,
                mainWindow: main,
                lastKeyWindow: main
            ),
            .host
        )
    }

    func testHostFocusRestrictsNothingWhileSheetFocusRestrictsToItsWindow() {
        let sheet = makeWindow()

        XCTAssertNil(ShortcutHintFocus.host.restrictedWindowID)
        XCTAssertNil(ShortcutHintFocus.unknown.restrictedWindowID)
        XCTAssertEqual(
            ShortcutHintFocus.sheet(ObjectIdentifier(sheet)).restrictedWindowID,
            ObjectIdentifier(sheet)
        )
    }

    /// Regression: a key window of ours that hosts no badges — Settings, a
    /// Sparkle prompt, an alert — must not black out the whole app. The app
    /// is still frontmost, so hints resolve against the main window.
    func testFocusFallsBackToMainWindowWhenAnUnregisteredWindowIsKey() {
        let host = makeWindow()

        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [host],
                isAppActive: true,
                keyWindow: makeWindow(),
                mainWindow: host,
                lastKeyWindow: nil
            ),
            .host
        )
    }

    /// Even with nothing to fall back on, an unregistered key window fails
    /// open rather than going foreign — only an inactive app is foreign.
    func testFocusIsUnknownForAnUnrelatedKeyWindowWithNoFallback() {
        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [makeWindow()],
                isAppActive: true,
                keyWindow: makeWindow(),
                mainWindow: nil,
                lastKeyWindow: nil
            ),
            .unknown
        )
    }

    /// A child window that is not a sheet — the toolbar, a popover — is the
    /// same app window to the user, so it must not narrow the hints.
    func testFocusTreatsANonSheetChildWindowAsHost() {
        let host = makeWindow()
        let child = makeWindow()
        host.addChildWindow(child, ordered: .above)

        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [host],
                isAppActive: true,
                keyWindow: child,
                mainWindow: host,
                lastKeyWindow: host
            ),
            .host
        )
    }

    func testFocusKeepsHostWhenCommandClearsKeyWindow() {
        let host = makeWindow()
        let child = makeWindow()
        host.addChildWindow(child, ordered: .above)
        child.orderFront(nil)

        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [host],
                isAppActive: true,
                keyWindow: nil,
                mainWindow: host,
                lastKeyWindow: child
            ),
            .host
        )
    }

    func testFocusFallsBackToMainWindowWhenNothingIsKey() {
        let host = makeWindow()

        XCTAssertEqual(
            ShortcutHintModifierFlagsSupport.focus(
                hostWindows: [host],
                isAppActive: true,
                keyWindow: nil,
                mainWindow: host,
                lastKeyWindow: nil
            ),
            .host
        )
    }

    func testHostActivityIgnoresUnrelatedKeyWindow() {
        XCTAssertFalse(
            ShortcutHintModifierFlagsSupport.isHostActive(
                hostWindows: [makeWindow()],
                isAppActive: true,
                keyWindow: makeWindow(),
                mainWindow: nil
            )
        )
    }
}
