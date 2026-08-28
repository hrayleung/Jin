import Foundation

enum AttachmentPromptRenderer {
    static func fallbackText(for file: FileContent) -> String {
        let filename = file.filename
        let mimeType = file.mimeType

        guard let trimmedExtracted = file.extractedText?.trimmedNonEmpty else {
            return "Attachment: \(filename) (\(mimeType))"
        }

        let isPDF = mimeType == "application/pdf"
        let kind = isPDF ? "PDF" : "File"
        let header = "\(kind): \(filename) (\(mimeType))"
        let note = "Extracted \(kind.lowercased()) text (formatting may be imperfect)."

        return "\(header)\n\n\(note)\n\n\(trimmedExtracted)"
    }
}
