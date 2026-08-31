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
        XCTAssertEqual(store.helpText("New Chat", for: .newChat), "New Chat (⌘N)")
    }

    func testSelectChatsHasItsOwnBinding() {
        let store = AppShortcutsStore(defaults: defaults)

        XCTAssertEqual(store.binding(for: .selectChats), .command("l", modifiers: [.shift, .command]))
        XCTAssertEqual(store.helpText("Select Chats", for: .selectChats), "Select Chats (⇧⌘L)")
    }

    /// ⌘A must stay with the system's text Select All, which reaches the first
    /// responder through the Edit menu — a scene-level command claiming it
    /// would break selecting text in the composer.
    func testSelectAllChatsDoesNotClaimPlainCommandA() {
        let store = AppShortcutsStore(defaults: defaults)
        let binding = store.binding(for: .selectAllChats)

        XCTAssertEqual(binding, .command("a", modifiers: [.option, .command]))
        XCTAssertNotEqual(binding, .command("a"))
        XCTAssertEqual(store.helpText("Select All", for: .selectAllChats), "Select All (⌥⌘A)")
    }

    /// A duplicate default is silently disabled by `normalizeConflictsIfNeeded`
    /// at load, so a new action shipping with a taken binding would just leave
    /// some other shortcut dead. Every default has to be unique and clear of
    /// the reserved system ones.
    func testEveryDefaultBindingIsUniqueAndUnreserved() {
        let store = AppShortcutsStore(defaults: defaults)
        var seen: [AppShortcutBinding: AppShortcutAction] = [:]

        for action in AppShortcutAction.allCases {
            guard let binding = action.defaultBinding else { continue }

            if let existing = seen[binding] {
                XCTFail("\(action) defaults to \(binding.displayLabel), already taken by \(existing).")
            }
            seen[binding] = action

            XCTAssertNil(
                store.fixedShortcutConflictMessage(for: binding),
                "\(action) defaults to a binding reserved by the system."
            )
            XCTAssertEqual(
                store.binding(for: action),
                binding,
                "\(action) lost its default binding at load, which means it collided with another action."
            )
        }
    }

    func testConflictingAssignmentDisablesPreviousAction() {
        let store = AppShortcutsStore(defaults: defaults)

        let result = store.setBinding(.command("n"), for: .toggleChatList)

        XCTAssertEqual(result.reassignedFrom, .newChat)
        XCTAssertEqual(store.binding(for: .toggleChatList), .command("n"))
        XCTAssertNil(store.binding(for: .newChat))
        XCTAssertTrue(store.disabledActions.contains(.newChat))
    }

    func testFixedSettingsShortcutCannotBeAssigned() {
        let store = AppShortcutsStore(defaults: defaults)

        let result = store.setBinding(.command(","), for: .newChat)

        XCTAssertEqual(result.rejectedByFixedShortcut, "⌘, is reserved for Settings.")
        XCTAssertNil(result.reassignedFrom)
        XCTAssertEqual(store.binding(for: .newChat), .command("n"))
        XCTAssertFalse(store.isCustomized(.newChat))
    }

    func testFixedCommandReturnShortcutCannotBeAssigned() {
        let store = AppShortcutsStore(defaults: defaults)
        let commandReturn = AppShortcutBinding(key: .returnKey, modifiers: [.command])

        let result = store.setBinding(commandReturn, for: .toggleChatList)

        XCTAssertEqual(result.rejectedByFixedShortcut, "⌘↩ is reserved for Send Message.")
        XCTAssertEqual(store.binding(for: .toggleChatList), .command("b"))
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

    func testLoadPreservesPersistedCustomBindingWhenItConflictsWithNewDefault() throws {
        let state = PersistedShortcutState(
            customBindings: [
                AppShortcutAction.attachFiles.rawValue: .command("m", modifiers: [.shift, .command])
            ],
            disabledActionIDs: []
        )
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: AppPreferenceKeys.keyboardShortcuts)

        let store = AppShortcutsStore(defaults: defaults)

        XCTAssertEqual(store.binding(for: .attachFiles), .command("m", modifiers: [.shift, .command]))
        XCTAssertNil(store.binding(for: .openModelPicker))
        XCTAssertTrue(store.disabledActions.contains(.openModelPicker))
    }

    func testLoadRestoresDefaultWhenPersistedCustomBindingIsNowReserved() throws {
        let state = PersistedShortcutState(
            customBindings: [
                AppShortcutAction.toggleChatList.rawValue: .command(",")
            ],
            disabledActionIDs: []
        )
        defaults.set(try JSONEncoder().encode(state), forKey: AppPreferenceKeys.keyboardShortcuts)

        let store = AppShortcutsStore(defaults: defaults)

        XCTAssertEqual(store.binding(for: .toggleChatList), .command("b"))
        XCTAssertFalse(store.isCustomized(.toggleChatList))
    }
}

private struct PersistedShortcutState: Codable {
    var customBindings: [String: AppShortcutBinding]
    var disabledActionIDs: [String]
}
