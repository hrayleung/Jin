import XCTest
@testable import Jin

final class AppShortcutBindingTests: XCTestCase {
    func testCommandBindingTrimsAndLowercasesCharacterInput() {
        XCTAssertEqual(
            AppShortcutBinding.command(" K "),
            AppShortcutBinding(key: .character("k"), modifiers: [.command])
        )
    }

    func testCommandBindingFallsBackToKForBlankInput() {
        XCTAssertEqual(
            AppShortcutBinding.command(" \n\t "),
            AppShortcutBinding(key: .character("k"), modifiers: [.command])
        )
    }
}
