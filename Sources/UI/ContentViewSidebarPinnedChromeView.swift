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
    var searchFieldFocus: FocusState<Bool>.Binding

    private var searchFieldIsActive: Bool {
        ContentViewSidebarPinnedChromeSupport.isSearchFieldActive(
            isFocused: searchFieldFocus.wrappedValue,
            searchText: searchText
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeaderView(
                assistantDisplayName: assistantDisplayName,
                extendsContentIntoTitlebar: extendsContentIntoTitlebar,
                titlebarLeadingInset: titlebarLeadingInset,
                titlebarTopInset: titlebarTopInset,
                onNewChat: onNewChat,
                onHideSidebar: onHideSidebar,
                shortcutsStore: shortcutsStore
            )

            searchField
        }
        .padding(.bottom, JinSpacing.small)
        .background(JinSemanticColor.canvas)
    }

    private var searchField: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(text: $searchText, prompt: Text("Search chats")) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused(searchFieldFocus)
            .accessibilityLabel("Search chats")
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(searchFieldIsActive ? JinSemanticColor.raisedSurface : JinSemanticColor.panelSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    searchFieldIsActive ? JinSemanticColor.borderEmphasized : JinSemanticColor.borderSubtle,
                    lineWidth: JinStrokeWidth.hairline
                )
        }
        .padding(.horizontal, JinSpacing.medium)
        .animation(.easeInOut(duration: 0.12), value: searchFieldIsActive)
    }
}
