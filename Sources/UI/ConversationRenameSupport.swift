import Foundation

enum ConversationRenameSupport {
    static func normalizedTitle(_ title: String) -> String? {
        title.trimmedNonEmpty
    }

    static func canSaveTitle(_ title: String) -> Bool {
        normalizedTitle(title) != nil
    }
}
