import AppKit
import SwiftUI
import XCTest
@testable import Jin

@MainActor
final class JinMenuSelectionItemTests: XCTestCase {
    private let choices = ["Native", "Mistral", "MinerU", "DeepSeek", "OpenRouter", "Firecrawl", "macOS Extract"]

    func testNativeMenuChecksOnlyTheSelectedChoice() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("NSHostingMenu requires macOS 14.4") }
        _ = NSApplication.shared

        for selected in choices {
            let menu = NSHostingMenu(rootView: choicesView(selected: selected))
            menu.update()

            XCTAssertEqual(menu.items.map(\.title), choices)
            XCTAssertEqual(menu.items.filter { $0.state == .on }.map(\.title), [selected])
            // A checkmark image on an unchecked NSMenuItem caused the original
            // bug. The native state column must own every selection mark.
            XCTAssertTrue(menu.items.allSatisfy { $0.image == nil })
        }
    }

    func testExistingMenuRefreshesItsSelection() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("NSHostingMenu requires macOS 14.4") }
        _ = NSApplication.shared
        let selection = MenuSelection()
        let menu = NSHostingMenu(rootView: ObservedChoices(choices: choices, selection: selection))
        menu.update()

        selection.selected = "MinerU"
        flushMenuUpdates()
        menu.update()

        XCTAssertEqual(menu.items.filter { $0.state == .on }.map(\.title), ["MinerU"])
        XCTAssertTrue(menu.items.allSatisfy { $0.image == nil })
    }

    func testNestedMenuUsesNativeSelectionState() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("NSHostingMenu requires macOS 14.4") }
        _ = NSApplication.shared
        let menu = NSHostingMenu(rootView: Menu("PDF handling") {
            choicesView(selected: "macOS Extract")
        })
        menu.update()
        let submenu = try XCTUnwrap(menu.items.first?.submenu)
        submenu.update()

        XCTAssertEqual(submenu.items.count, choices.count)
        XCTAssertEqual(submenu.items.filter { $0.state == .on }.map(\.title), ["macOS Extract"])
        XCTAssertTrue(submenu.items.allSatisfy { $0.image == nil })
    }

    func testChoosingAndReselectingAnItemDispatchesItsAction() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("NSHostingMenu requires macOS 14.4") }
        _ = NSApplication.shared
        let selection = MenuSelection()
        let menu = NSHostingMenu(rootView: ObservedChoices(choices: choices, selection: selection))
        menu.update()

        menu.performActionForItem(at: 2)
        XCTAssertEqual(selection.selected, "MinerU")
        XCTAssertEqual(selection.actions, 1)

        flushMenuUpdates()
        menu.update()
        menu.performActionForItem(at: 2)
        flushMenuUpdates()
        menu.update()
        XCTAssertEqual(selection.selected, "MinerU")
        XCTAssertEqual(selection.actions, 2)
        XCTAssertEqual(menu.items.filter { $0.state == .on }.map(\.title), ["MinerU"])
    }

    func testContextCacheMenuPreservesActionsAndSupportedChoices() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("NSHostingMenu requires macOS 14.4") }
        _ = NSApplication.shared
        var selectedMode = ContextCacheMode.off
        let menu = NSHostingMenu(rootView: ContextCacheControlMenuView(
            effectiveMode: .off,
            supportsExplicitContextCacheMode: false,
            showsReset: false,
            onTurnOff: { selectedMode = .off },
            onSetImplicit: { selectedMode = .implicit },
            onSetExplicit: { selectedMode = .explicit },
            onConfigure: {},
            onReset: {}
        ))
        menu.update()

        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title), ["Off", "Implicit", "Configure…"])
        XCTAssertEqual(menu.items.filter { $0.state == .on }.map(\.title), ["Off"])
        menu.performActionForItem(at: 1)
        XCTAssertEqual(selectedMode, .implicit)
    }

    private func choicesView(selected: String, onSelect: @escaping (String) -> Void = { _ in }) -> some View {
        ForEach(choices, id: \.self) { choice in
            JinMenuSelectionItem(choice, isSelected: selected == choice) {
                onSelect(choice)
            }
        }
    }

    private func flushMenuUpdates() {
        // NSHostingMenu schedules observed SwiftUI changes on the next run-loop
        // turn, just as it does between dismissing and reopening a menu.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

@MainActor
private final class MenuSelection: ObservableObject {
    @Published var selected = "Native"
    var actions = 0
}

private struct ObservedChoices: View {
    let choices: [String]
    @ObservedObject var selection: MenuSelection

    var body: some View {
        ForEach(choices, id: \.self) { choice in
            JinMenuSelectionItem(choice, isSelected: selection.selected == choice) {
                selection.selected = choice
                selection.actions += 1
            }
        }
    }
}
