import Foundation

enum ContentViewSidebarPinnedChromeSupport {
    static func isSearchFieldActive(
        isFocused: Bool,
        searchText: String
    ) -> Bool {
        isFocused || searchText.trimmedNonEmpty != nil
    }
}
