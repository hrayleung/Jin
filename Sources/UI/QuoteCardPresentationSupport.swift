import Foundation

enum QuoteCardPresentationSupport {
    static func sourceLine(
        role: MessageRole?,
        modelName: String?
    ) -> String {
        let base = sourceRoleLabel(role)
        guard let modelName = modelName?.trimmedNonEmpty else { return base }
        return "\(base) · \(modelName)"
    }

    private static func sourceRoleLabel(_ role: MessageRole?) -> String {
        switch role {
        case .assistant?:
            "Assistant"
        case .user?:
            "User"
        case .system?:
            "System"
        case .tool?:
            "Tool"
        case nil:
            "Quoted"
        }
    }
}
