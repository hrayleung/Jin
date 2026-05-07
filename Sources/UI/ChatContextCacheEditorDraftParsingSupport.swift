import Foundation

extension ChatAuxiliaryControlSupport {
    static func normalizedContextCacheTextField(_ value: String?) -> String? {
        value?.trimmedNonEmpty
    }

    static func positiveContextCacheInteger(from draft: String) -> Int? {
        guard let trimmed = draft.trimmedNonEmpty,
              let value = Int(trimmed),
              value > 0 else {
            return nil
        }
        return value
    }
}
