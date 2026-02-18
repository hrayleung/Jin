import XCTest
@testable import Jin

@MainActor
final class AppShortcutsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppShortcutsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultBindingsAreAvailable() {
        let store = AppShortcutsStore(defaults: defaults)

        XCTAssertEqual(store.binding(for: .toggleChatList), .command("b"))
        XCTAssertEqual(store.binding(for: .newChat), .command("n"))
        XCTAssertEqual(store.binding(for: .openModelPicker), .command("m", modifiers: [.shift, .command]))
        XCTAssertEqual(store.binding(for: .deleteChat), AppShortcutBinding(key: .delete, modifiers: [.command]))
    }

    func testConflictingAssignmentDisablesPreviousAction() {
        let store = AppShortcutsStore(defaults: defaults)

        let result = store.setBinding(.command("n"), for: .toggleChatList)

        XCTAssertEqual(result.reassignedFrom, .newChat)
        XCTAssertEqual(store.binding(for: .toggleChatList), .command("n"))
        XCTAssertNil(store.binding(for: .newChat))
        XCTAssertTrue(store.disabledActions.contains(.newChat))
    }

    func testCustomBindingPersistsAcrossStoreReload() {
        let store = AppShortcutsStore(defaults: defaults)
        store.setBinding(.command("1"), for: .newChat)

        let reloaded = AppShortcutsStore(defaults: defaults)
        XCTAssertEqual(reloaded.binding(for: .newChat), .command("1"))
    }

    func testRestoreDefaultRemovesCustomizationAndDisabledState() {
        let store = AppShortcutsStore(defaults: defaults)
        store.setBinding(nil, for: .newChat)
        XCTAssertNil(store.binding(for: .newChat))

        store.restoreDefault(for: .newChat)
        XCTAssertEqual(store.binding(for: .newChat), .command("n"))
        XCTAssertFalse(store.disabledActions.contains(.newChat))
        XCTAssertFalse(store.isCustomized(.newChat))
    }
}
