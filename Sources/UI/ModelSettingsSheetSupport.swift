import Foundation

enum ModelSettingsSheetSupport {
    enum OptionalPositiveIntegerDraft: Equatable {
        case empty
        case value(Int)
        case invalid
    }

    static func positiveInteger(from draft: String) -> Int? {
        guard let trimmed = draft.trimmedNonEmpty,
              let value = Int(trimmed),
              value > 0 else { return nil }
        return value
    }

    static func optionalPositiveInteger(from draft: String) -> OptionalPositiveIntegerDraft {
        guard let trimmed = draft.trimmedNonEmpty else { return .empty }
        guard let value = Int(trimmed), value > 0 else { return .invalid }
        return .value(value)
    }
}
