import Foundation

enum AssistantSettingsEditorSupport {
    enum OptionalPositiveIntegerDraft: Equatable {
        case clear
        case value(Int)
        case invalid
    }

    static func normalizedCustomReplyLanguage(_ language: String) -> String? {
        language.trimmedNonEmpty
    }

    static func normalizedAssistantDescription(_ description: String) -> String? {
        description.trimmedNonEmpty
    }

    static func normalizedIcon(_ icon: String) -> String? {
        icon.trimmedNonEmpty
    }

    static func optionalPositiveIntegerDraft(from draft: String) -> OptionalPositiveIntegerDraft {
        guard let trimmed = draft.trimmedNonEmpty else { return .clear }
        guard let value = Int(trimmed), value > 0 else { return .invalid }
        return .value(value)
    }
}
