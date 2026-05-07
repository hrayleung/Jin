import Foundation

enum ResponseCompletionNotificationSupport {
    static let fallbackTitle = "Jin"
    static let fallbackBody = "Your assistant reply is ready."

    static func notificationTitle(from conversationTitle: String) -> String {
        conversationTitle.trimmedNonEmpty ?? fallbackTitle
    }

    static func notificationBody(from replyPreview: String?) -> String {
        replyPreview?.trimmedNonEmpty ?? fallbackBody
    }
}
