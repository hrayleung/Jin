import Foundation

enum AddModelSheetSupport {
    static func normalizedNickname(_ nickname: String) -> String {
        nickname.trimmed
    }

    static func normalizedModelID(_ modelID: String) -> String {
        modelID.trimmed
    }

    static func resolvedModelName(
        nickname: String,
        modelID: String
    ) -> String {
        normalizedNickname(nickname).isEmpty
            ? normalizedModelID(modelID)
            : normalizedNickname(nickname)
    }

    static func canAddModel(modelID: String) -> Bool {
        normalizedModelID(modelID).isEmpty == false
    }
}
