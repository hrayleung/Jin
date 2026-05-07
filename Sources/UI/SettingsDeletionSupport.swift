import Foundation

enum SettingsDeletionSupport {
    static func providerDeletionMessage(providerName: String, chatCount: Int) -> String {
        guard chatCount > 0 else {
            return "This will permanently delete \u{201C}\(providerName)\u{201D}."
        }

        return """
        This will permanently delete \u{201C}\(providerName)\u{201D}.

        It is currently used by \(chatCount) chat\(chatCount == 1 ? "" : "s"). Those chats will need a different provider selected.
        """
    }

    static func serverDeletionMessage(serverName: String) -> String {
        "This will permanently delete \u{201C}\(serverName)\u{201D}."
    }
}
