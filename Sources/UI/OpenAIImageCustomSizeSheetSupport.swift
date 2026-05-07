import Foundation

enum OpenAIImageCustomSizeSheetSupport {
    static let invalidSizeMessage = "Enter a size like `2048x1152`."

    static func initialDraftText(currentSize: OpenAIImageSize?) -> String {
        guard let currentSize, currentSize.isAuto == false else { return "" }
        return currentSize.displayName
    }

    static func normalizedDraftText(_ draftText: String) -> String {
        draftText.trimmedLowercased
    }

    static func parsedSize(from draftText: String) -> OpenAIImageSize? {
        let normalized = normalizedDraftText(draftText)
        guard !normalized.isEmpty else { return nil }
        return OpenAIImageSize(rawValue: normalized)
    }

    static func validationError(draftText: String, modelID: String) -> String? {
        guard let parsedSize = parsedSize(from: draftText) else {
            return invalidSizeMessage
        }
        return OpenAIImageModelSupport.validate(size: parsedSize, for: modelID)
    }

    static func displayedValidationError(
        explicitError: String?,
        draftText: String,
        modelID: String
    ) -> String? {
        if let explicitError {
            return explicitError
        }
        guard !normalizedDraftText(draftText).isEmpty else { return nil }
        return validationError(draftText: draftText, modelID: modelID)
    }

    static func canSubmit(draftText: String) -> Bool {
        !normalizedDraftText(draftText).isEmpty
    }
}
