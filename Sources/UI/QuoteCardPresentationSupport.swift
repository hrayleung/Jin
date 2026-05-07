import Foundation

enum QuoteCardPresentationSupport {
    struct ComposerHeader {
        let prefix: String
        let modelName: String?
    }

    static func sourceLine(
        role: MessageRole?,
        modelName: String?
    ) -> String {
        let base = sourceRoleLabel(role)
        guard let modelName = modelName?.trimmedNonEmpty else { return base }
        return "\(base) · \(modelName)"
    }

    static func composerHeader(
        role: MessageRole?,
        modelName: String?
    ) -> ComposerHeader {
        let trimmedModel = modelName?.trimmedNonEmpty
        let prefix: String
        switch role {
        case .assistant?, nil:
            prefix = trimmedModel == nil ? "Quoted reply" : "Replying to"
        case .user?:
            prefix = "Quoting your message"
        case .system?:
            prefix = "Quoting system"
        case .tool?:
            prefix = "Quoting tool"
        }
        return ComposerHeader(prefix: prefix, modelName: trimmedModel)
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
