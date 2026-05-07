import Foundation

enum AttachmentConstants {
    static let maxPDFExtractedCharacters = 120_000
    static let maxSpreadsheetExtractedCharacters = 120_000
    static let maxMistralOCRImagesToAttach = 8
    static let maxMistralOCRTotalImageBytes = 12 * 1024 * 1024
}

struct AttachmentImportError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

struct DraftAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let fileURL: URL
    let extractedText: String?

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isVideo: Bool { mimeType.hasPrefix("video/") }
    var isAudio: Bool { mimeType.hasPrefix("audio/") }
    var isPDF: Bool { mimeType == "application/pdf" }
}
