import Foundation

enum AddModelSheetSupport {
    static func normalizedNickname(_ nickname: String) -> String {
        nickname.trimmed
    }

    static func normalizedModelID(_ modelID: String, providerType: ProviderType? = nil) -> String {
        let trimmed = modelID.trimmed
        guard providerType == .modal else { return trimmed }
        return ModalEndpointSupport.normalizedModelID(from: trimmed)
    }

    static func resolvedModelName(
        nickname: String,
        modelID: String,
        providerType: ProviderType? = nil
    ) -> String {
        let normalizedID = normalizedModelID(modelID, providerType: providerType)
        if !normalizedNickname(nickname).isEmpty {
            return normalizedNickname(nickname)
        }
        if providerType == .modal, let endpointName = ModalEndpointSupport.displayName(forModelID: normalizedID) {
            return endpointName
        }
        return normalizedID
    }

    static func canAddModel(modelID: String, providerType: ProviderType? = nil) -> Bool {
        normalizedModelID(modelID, providerType: providerType).isEmpty == false
    }
}
