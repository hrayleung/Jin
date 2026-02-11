import Foundation

enum AttachmentPromptRenderer {
    static func fallbackText(for file: FileContent) -> String {
        let filename = file.filename
        let mimeType = file.mimeType

        let trimmedExtracted = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedExtracted, !trimmedExtracted.isEmpty else {
            return "Attachment: \(filename) (\(mimeType))"
        }

        let isPDF = mimeType == "application/pdf"
        let kind = isPDF ? "PDF" : "File"
        let header = "\(kind): \(filename) (\(mimeType))"
        let note = "The following text was extracted from the \(kind.lowercased()). Treat it as the \(kind.lowercased())'s contents (formatting may be imperfect)."

        return "\(header)\n\n\(note)\n\n\(trimmedExtracted)"
    }
}
