import SwiftUI

struct ContentViewSidebarPinnedChromeView: View {
    let assistantDisplayName: String
    let extendsContentIntoTitlebar: Bool
    let titlebarLeadingInset: CGFloat
    let titlebarTopInset: CGFloat
    let shortcutsStore: AppShortcutsStore
    let onNewChat: () -> Void
    let onHideSidebar: () -> Void
    @Binding var searchText: String
    @Binding var isChatSelectionModeActive: Bool
    var searchFieldFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeaderView(
                assistantDisplayName: assistantDisplayName,
                extendsContentIntoTitlebar: extendsContentIntoTitlebar,
                titlebarLeadingInset: titlebarLeadingInset,
                titlebarTopInset: titlebarTopInset,
                onNewChat: onNewChat,
                onHideSidebar: onHideSidebar,
                isChatSelectionModeActive: $isChatSelectionModeActive,
                shortcutsStore: shortcutsStore
            )

            searchField
        }
        .padding(.bottom, JinSpacing.small)
        // No background — sidebar chrome inherits NavigationSplitView's
        // native sidebar material (Liquid Glass on macOS 26).
    }

    private var searchField: some View {
        JinSearchField(text: $searchText, prompt: "Search chats", focus: searchFieldFocus)
            .help(shortcutsStore.helpText("Search chats", for: .searchChats))
        .shortcutHint(.searchChats, placement: .trailing)
        .padding(.horizontal, JinSpacing.medium)
    }
}
