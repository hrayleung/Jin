import SwiftUI

/// Title-bar sidebar affordance. Replaces NavigationSplitView's system
/// `.sidebarToggle`, which on macOS 26 can render the Liquid Glass control
/// without writing `columnVisibility` (so the click appears to do nothing).
/// Attach this once, on the sidebar column. The item migrates into the
/// remaining title bar when the sidebar collapses — do not add a second copy.
struct MainSidebarToggleButton: View {
    @EnvironmentObject private var shortcutsStore: AppShortcutsStore

    let isSidebarVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.leading")
        }
        .help(shortcutsStore.helpText(helpText, for: .toggleChatList))
        .accessibilityLabel(helpText)
        .shortcutHint(.toggleChatList, placement: .overlayBottom)
    }

    private var helpText: String {
        isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
    }
}
