import XCTest
@testable import Jin

final class ShortcutHintLabelSupportTests: XCTestCase {
    func testCompactLabelOmitsHeldCommand() {
        XCTAssertEqual(
            ShortcutHintLabelSupport.compactLabel(
                for: .command("n"),
                heldModifiers: [.command]
            ),
            "N"
        )
    }

    func testCompactLabelKeepsUnheldShift() {
        XCTAssertEqual(
            ShortcutHintLabelSupport.compactLabel(
                for: .command("a", modifiers: [.shift, .command]),
                heldModifiers: [.command]
            ),
            "⇧A"
        )
    }

    func testCompactLabelOmitsHeldShiftAndCommand() {
        XCTAssertEqual(
            ShortcutHintLabelSupport.compactLabel(
                for: .command("a", modifiers: [.shift, .command]),
                heldModifiers: [.shift, .command]
            ),
            "A"
        )
    }

    func testCompactLabelHidesWhenHeldModifiersAreNotASubset() {
        XCTAssertNil(
            ShortcutHintLabelSupport.compactLabel(
                for: .command("n"),
                heldModifiers: [.shift, .command]
            )
        )
    }

    func testCompactLabelReturnsNilForMissingBinding() {
        XCTAssertNil(
            ShortcutHintLabelSupport.compactLabel(
                for: nil,
                heldModifiers: [.command]
            )
        )
    }

    func testCompactLabelShowsSpecialKeyGlyph() {
        let binding = AppShortcutBinding(key: .delete, modifiers: [.command])
        XCTAssertEqual(
            ShortcutHintLabelSupport.compactLabel(
                for: binding,
                heldModifiers: [.command]
            ),
            "⌫"
        )
    }

    func testHelpTextAppendsFullShortcut() {
        XCTAssertEqual(
            ShortcutHintLabelSupport.helpText("New Chat", binding: .command("n")),
            "New Chat (⌘N)"
        )
    }

    func testHelpTextKeepsTitleWhenBindingIsMissing() {
        XCTAssertEqual(
            ShortcutHintLabelSupport.helpText("New Chat", binding: nil),
            "New Chat"
        )
    }
}
