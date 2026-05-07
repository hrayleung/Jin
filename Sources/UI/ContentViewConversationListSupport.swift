import Foundation

enum ContentViewConversationListSupport {
    static func normalizedSearchQuery(_ searchText: String) -> String {
        searchText.trimmedNonEmpty ?? ""
    }
}
